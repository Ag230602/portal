-- Parenthesize JSON extraction before containment comparisons.
-- Without parentheses, PostgreSQL can apply -> to a boolean containment result.
begin;
CREATE OR REPLACE FUNCTION public.naac_portal(action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 uid uuid=auth.uid();account auth.users%rowtype;member public.naac_members%rowtype;old public.naac_submissions%rowtype;
 item jsonb;raw jsonb;definition jsonb;f jsonb;value jsonb;clean jsonb='{}';rid uuid;eid uuid;t timestamptz=now();newstatus text;
 files jsonb;result jsonb;document public.naac_evidence%rowtype;report public.naac_reports%rowtype;sections jsonb;sources jsonb;snapshot jsonb;
 data_year text;data_department text;data_panel text;role_value text;object_meta jsonb;expected_version integer;missing text[];
begin
 if uid is null then raise exception 'Sign in with Google to access the portal.' using errcode='42501';end if;
 select * into account from auth.users where id=uid;
 if account.email_confirmed_at is null or not exists(select 1 from auth.identities where user_id=uid and provider='google') then raise exception 'A verified Google account is required.' using errcode='42501';end if;
 -- Only a trusted auth identity determines the email and default role. User metadata cannot grant permissions.
 insert into public.naac_members(email,user_id,name,department) values(lower(account.email),uid,coalesce(account.raw_user_meta_data->>'full_name',account.email),'Mechanical Engineering') on conflict(email) do update set user_id=excluded.user_id where naac_members.user_id is null or naac_members.user_id=excluded.user_id;
 select * into member from public.naac_members where user_id=uid;
 if member.user_id is null then raise exception 'Account membership could not be established.';end if;
 member.role=public.naac_role();
 if action='load' then
 return jsonb_build_object('user',jsonb_build_object('email',member.email,'name',member.name,'role',member.role,'department','Mechanical Engineering','approved',public.naac_is_owner() or public.naac_can_fill_forms()),
 'departments',(select coalesce(jsonb_agg(name order by name),'[]') from public.naac_departments where name='Mechanical Engineering'),
 'entries',(select coalesce(jsonb_agg(s.payload order by s.updated_at desc),'[]') from public.naac_submissions s where public.naac_can_read(s.id)),
 'evidence',(select coalesce(jsonb_agg(e.payload),'[]') from public.naac_evidence e where public.naac_can_read(e.submission_id)),
 'reports',(select coalesce(jsonb_agg(r.payload order by r.created_at desc),'[]') from public.naac_reports r where member.role='admin'),
 'users',(select coalesce(jsonb_agg(jsonb_build_object('email',email,'name',name,'role',role,'department',department,'owner',user_id=(select user_id from public.naac_owner))),'[]') from public.naac_members where member.role='admin'),
 'audit',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from (select a.id,a.action,a.entity_id,a.created_at,m.email as created_by from public.naac_audit a join public.naac_members m on m.user_id=a.created_by where member.role='admin' order by a.created_at desc limit 200) a));
 end if;
 -- Deny privileged actions centrally, including old coordinator and onboarding endpoints.
 if member.role<>'admin' then
 if action not in ('save','submit','registerEvidence','evidenceDownload') then raise exception 'Only the portal owner can access responses, summaries, or administration.' using errcode='42501';end if;
 end if;
 if action in ('approveStudents','user','revokeStudent','department','onboard') then
 raise exception 'Student approval is no longer required. Sign in with Google to fill the Mechanical Engineering forms.' using errcode='42501';
 elsif action in ('save','submit') then
 raw=naac_portal.payload->'entry';
 if raw->>'department' is distinct from 'Mechanical Engineering' then raise exception 'Only Mechanical Engineering forms are accepted.' using errcode='42501';end if;
 if member.role<>'admin' then raw=raw||jsonb_build_object('email',member.email);end if;
 select d.definition into definition from public.naac_panel_definitions d where id=raw->>'panel';
 if definition is null or raw->>'year' not in ('2023–24','2024–25','2025–26') then raise exception 'Select a valid annexure and academic year.';end if;
 if raw->>'panel'='gender' and member.role='respondent' then raise exception 'Gender-equality data is restricted to coordinators.' using errcode='42501';end if;
 rid=coalesce(nullif(raw->>'id','')::uuid,gen_random_uuid());select * into old from public.naac_submissions where id=rid for update;
 if nullif(raw->>'id','') is not null and old.id is null then raise exception 'Record not found.';end if;
 if old.id is not null then
 if not public.naac_can_upload(rid) then raise exception 'Submitted data is locked or access is denied.' using errcode='42501';end if;
 if old.version<>(raw->>'version')::integer then raise exception 'This record changed. Reload before saving.';end if;
 if (old.department<>raw->>'department' or old.year<>raw->>'year' or old.panel<>raw->>'panel') and exists(select 1 from public.naac_evidence where submission_id=rid) then raise exception 'Records with preserved evidence cannot change annexure, year, or department.';end if;
 end if;
 if jsonb_typeof(raw->'data')<>'object' then raise exception 'Invalid record data.';end if;
 for f in select jsonb_array_elements(definition->'fields') loop
 value=raw->'data'->(f->>'label');if value is null then continue;end if;
 if f->>'type'='multi' then
 if jsonb_typeof(value)<>'array' then raise exception 'Invalid multiple selection.';end if;
 if exists(select 1 from jsonb_array_elements(value) v where not(f->'options' @> jsonb_build_array(v))) then raise exception 'Invalid multiple selection option.';end if;
 else
 if jsonb_typeof(value)<>'string' or length(value#>>'{}')>12000 then raise exception 'Invalid field value: %',f->>'label';end if;
 if f?'options' and value<>'""'::jsonb and not(f->'options' @> jsonb_build_array(value)) then raise exception 'Invalid option: %',f->>'label';end if;
 if f->>'type'='number' and value<>'""'::jsonb and (value#>>'{}')!~'^[0-9]+$' then raise exception 'Enter a non-negative whole number: %',f->>'label';end if;
 if f->>'type'='date' and value<>'""'::jsonb then perform (value#>>'{}')::date;end if;
 end if;clean=clean||jsonb_build_object(f->>'label',value);end loop;
 if nullif(clean->>'Start Date','') is not null and nullif(clean->>'End Date','') is not null and (clean->>'End Date')::date<(clean->>'Start Date')::date then raise exception 'End date must follow start date.';end if;
 newstatus=case when action='submit' then 'Submitted' else 'Draft' end;
 item=jsonb_build_object('id',rid,'panel',raw->>'panel','year',raw->>'year','department',raw->>'department','respondent',left(coalesce(raw->>'respondent',''),200),'designation',left(coalesce(raw->>'designation',''),200),'email',left(coalesce(raw->>'email',''),200),'date',coalesce(raw->>'date',''),'data',clean,'status',newstatus,'createdBy',coalesce(old.payload->>'createdBy',member.email),'createdAt',coalesce(old.payload->>'createdAt',t::text),'updatedAt',t,'version',coalesce(old.version,0)+1);
 if action='submit' then
 missing=public.naac_missing(item);if cardinality(missing)>0 then raise exception 'Complete required fields: %',array_to_string(missing,', ');end if;
 if item->>'email'!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Enter a valid respondent email.';end if;perform (item->>'date')::date;
 end if;
 insert into public.naac_submissions(id,created_by,department,year,panel,status,version,payload) values(rid,coalesce(old.created_by,uid),item->>'department',item->>'year',item->>'panel',newstatus,(item->>'version')::integer,item)
 on conflict(id) do update set department=excluded.department,year=excluded.year,panel=excluded.panel,status=excluded.status,version=excluded.version,payload=excluded.payload,updated_at=t;
 if action='submit' then select coalesce(jsonb_agg(e.payload),'[]') into files from public.naac_evidence e where submission_id=rid;insert into public.naac_revisions(submission_id,payload,created_by) values(rid,jsonb_build_object('entry',item,'evidence',files),uid);end if;
 result=jsonb_build_object('entry',item);
 elsif action='history' then
 rid=(naac_portal.payload->>'id')::uuid;if not public.naac_can_read(rid) then raise exception 'Access denied.' using errcode='42501';end if;
 return jsonb_build_object('history',(select coalesce(jsonb_agg(jsonb_build_object('payload',r.payload,'created_at',r.created_at,'created_by',m.email) order by r.created_at desc),'[]') from public.naac_revisions r join public.naac_members m on m.user_id=r.created_by where submission_id=rid));
 elsif action='registerEvidence' then
 rid=(naac_portal.payload->>'entryId')::uuid;eid=(naac_portal.payload->>'id')::uuid;select * into old from public.naac_submissions where id=rid for update;
 if not public.naac_can_upload(rid) then raise exception 'Save a draft or return this submission before attaching evidence.' using errcode='42501';end if;
 if naac_portal.payload->>'objectKey'<>rid::text||'/'||eid::text then raise exception 'Invalid object path.';end if;
 select metadata into object_meta from storage.objects where bucket_id='naac-evidence' and name=naac_portal.payload->>'objectKey' and owner_id=uid::text;
 if object_meta is null then raise exception 'Upload the original file first.';end if;
 if (object_meta->>'size')::bigint<> (naac_portal.payload->>'size')::bigint or (naac_portal.payload->>'size')::bigint not between 1 and 20971520 then raise exception 'Invalid file size.';end if;
 if naac_portal.payload->>'name'!~*'\.(pdf|docx?|xlsx?|csv|pptx?|png|jpe?g|webp|txt)$' then raise exception 'Unsupported file extension.';end if;
 select d.definition into definition from public.naac_panel_definitions d where id=old.panel;
 if not(definition->'evidence' @> jsonb_build_array(naac_portal.payload->>'type')) then raise exception 'Invalid document type.';end if;
 item=jsonb_build_object('id',eid,'entryId',rid,'name',left(naac_portal.payload->>'name',255),'type',naac_portal.payload->>'type','size',(naac_portal.payload->>'size')::bigint,'year',old.year,'department',old.department,'parameter',old.panel,'activity',coalesce(old.payload->'data'->>'Title of the project',old.payload->'data'->>'Seminar topic',old.payload->'data'->>(definition->'fields'->0->>'label'),'Record'),'uploadedBy',member.email,'uploadedAt',t,'status','Unverified','comments','');
 insert into public.naac_evidence values(eid,rid,naac_portal.payload->>'objectKey',item,t,uid);result=jsonb_build_object('evidence',item);
 elsif action='evidenceDownload' then
 select * into document from public.naac_evidence where id=(naac_portal.payload->>'id')::uuid;
 if document.id is null or not public.naac_can_read(document.submission_id) then raise exception 'Document not found.' using errcode='42501';end if;
 return jsonb_build_object('objectKey',document.object_key,'name',document.payload->>'name');
 elsif action='verifyEvidence' then
 select * into document from public.naac_evidence where id=(naac_portal.payload->>'id')::uuid for update;select * into old from public.naac_submissions where id=document.submission_id;
 if document.id is null or not(member.role='admin' or member.role='coordinator' and old.department=member.department) then raise exception 'Coordinator access required.' using errcode='42501';end if;
 if naac_portal.payload->>'status' not in ('Verified','Unverified','Needs correction') then raise exception 'Invalid evidence status.';end if;
 item=document.payload||jsonb_build_object('status',naac_portal.payload->>'status','comments',left(coalesce(naac_portal.payload->>'comments',''),12000));update public.naac_evidence set payload=item where id=document.id;result=jsonb_build_object('evidence',item);rid=document.submission_id;
 elsif action='review' then
 rid=(naac_portal.payload->>'id')::uuid;select * into old from public.naac_submissions where id=rid for update;
 if old.id is null or not(member.role='admin' or member.role='coordinator' and old.department=member.department) then raise exception 'Coordinator access required.' using errcode='42501';end if;
 newstatus=naac_portal.payload->>'status';if old.status not in ('Submitted','Department approved') or newstatus not in ('Department approved','Approved','Returned') then raise exception 'Invalid review transition.';end if;
 if newstatus='Approved' and member.role<>'admin' then raise exception 'Final approval requires the NAAC coordinator.' using errcode='42501';end if;
 if newstatus='Returned' and coalesce(trim(naac_portal.payload->>'comment'),'')='' then raise exception 'Explain the correction required.';end if;
 if newstatus<>'Returned' and (cardinality(public.naac_missing(old.payload))>0 or not exists(select 1 from public.naac_evidence e where submission_id=rid and e.payload->>'status'='Verified')) then raise exception 'Complete all required information and verify supporting evidence before approval.';end if;
 item=old.payload||jsonb_build_object('status',newstatus,'comment',left(coalesce(naac_portal.payload->>'comment',''),12000),'updatedAt',t,'version',old.version+1);
 update public.naac_submissions set payload=item,status=newstatus,version=version+1,updated_at=t where id=rid;
 insert into public.naac_reviews(submission_id,decision,comments,created_by) values(rid,newstatus,coalesce(naac_portal.payload->>'comment',''),uid);result=jsonb_build_object('entry',item);
 elsif action='createReport' then
 if member.role='respondent' then raise exception 'Coordinator access required.' using errcode='42501';end if;
 raw=naac_portal.payload->'report';rid=gen_random_uuid();data_year=coalesce(raw->>'year','');data_department=case when member.role='coordinator' then member.department else coalesce(raw->>'department','') end;data_panel=coalesce(raw->>'parameter','');
 select coalesce(jsonb_agg(jsonb_build_object('entry',s.payload,'evidence',(select coalesce(jsonb_agg(e.payload),'[]') from public.naac_evidence e where e.submission_id=s.id))),'[]') into snapshot from public.naac_submissions s where public.naac_can_read(s.id) and s.status in ('Submitted','Department approved','Approved') and (data_year='' or s.year=data_year) and (data_department='' or s.department=data_department) and (data_panel='' or s.panel=data_panel);
 if jsonb_typeof(raw->'sourceSnapshots') is distinct from 'array' then raise exception 'Invalid source snapshots.';end if;
 -- Fail on concurrent changes instead of attaching sources newer than those summarized.
 if exists(select 1 from jsonb_array_elements(snapshot) s where not exists(select 1 from jsonb_array_elements(raw->'sourceSnapshots') supplied where (supplied->'entry')=(s->'entry') and (supplied->'evidence') @> (s->'evidence') and (supplied->'evidence') <@ (s->'evidence'))) or jsonb_array_length(snapshot)<>jsonb_array_length(raw->'sourceSnapshots') then raise exception 'Source records changed while summarizing. Generate the report again.';end if;
 sections=raw->'sections';if jsonb_typeof(sections)<>'array' then raise exception 'Invalid report sections.';end if;
 for f in select jsonb_array_elements(sections) loop
 if jsonb_typeof(f->'text')<>'string' or jsonb_typeof(f->'heading')<>'string' or jsonb_typeof(f->'sources')<>'array' then raise exception 'Invalid report section.';end if;
 if exists(select 1 from jsonb_array_elements_text(f->'sources') sid where not exists(select 1 from jsonb_array_elements(snapshot) s where s->'entry'->>'id'=sid)) then raise exception 'Unknown report source.';end if;
 end loop;
 item=jsonb_build_object('id',rid,'title','NAAC Point-5 Consolidated Report','year',data_year,'department',data_department,'parameter',data_panel,'mode',case when raw->>'mode'='AI-generated' then 'AI-generated' else 'Count-based' end,'status','Draft','sections',sections,'createdAt',t,'createdBy',member.email,'version',1,'sourceSnapshots',snapshot);
 insert into public.naac_reports values(rid,nullif(data_department,''),item,t,uid);result=jsonb_build_object('report',item);
 elsif action='updateReport' then
 raw=naac_portal.payload->'report';rid=(raw->>'id')::uuid;select * into report from public.naac_reports where id=rid for update;
 if report.id is null or member.role='respondent' or not(member.role='admin' or report.created_by=uid) then raise exception 'Coordinator access required.' using errcode='42501';end if;
 if (raw->>'version')::integer<>(report.payload->>'version')::integer then raise exception 'Report changed. Reload before saving.';end if;
 if raw->>'status' not in ('Draft','Approved','Returned') or raw->>'status'='Approved' and member.role<>'admin' then raise exception 'Invalid approval permissions.' using errcode='42501';end if;
 sections=raw->'sections';if jsonb_typeof(sections)<>'array' then raise exception 'Invalid sections.';end if;
 for f in select jsonb_array_elements(sections) loop
 if jsonb_typeof(f->'text')<>'string' or jsonb_typeof(f->'heading')<>'string' or jsonb_typeof(f->'sources')<>'array' then raise exception 'Invalid report section.';end if;
 if exists(select 1 from jsonb_array_elements_text(f->'sources') sid where not exists(select 1 from jsonb_array_elements(report.payload->'sourceSnapshots') s where s->'entry'->>'id'=sid)) then raise exception 'Unknown report source.';end if;end loop;
 item=report.payload||jsonb_build_object('sections',sections,'status',raw->>'status','comment',coalesce(raw->>'comment',''),'version',(report.payload->>'version')::integer+1);update public.naac_reports set payload=item where id=rid;result=jsonb_build_object('report',item);
 elsif action='backup' then
 if member.role<>'admin' then raise exception 'Administrator access required.' using errcode='42501';end if;
 result=jsonb_build_object('exportedAt',t,'departments',(select coalesce(jsonb_agg(to_jsonb(d)),'[]') from public.naac_departments d),'users',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.naac_members m),'submissions',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.naac_submissions s),'submission_revisions',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.naac_revisions r),'evidence_documents',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from public.naac_evidence e),'coordinator_reviews',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.naac_reviews r),'ai_summaries',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.naac_reports r),'audit_logs',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.naac_audit a));
 else raise exception 'Unknown action.';end if;
 insert into public.naac_audit(action,entity_id,created_by) values(action,coalesce(rid::text,naac_portal.payload->>'email',naac_portal.payload->>'name',uid::text),uid);
 return coalesce(result,jsonb_build_object('ok',true));
end $function$

;


commit;
