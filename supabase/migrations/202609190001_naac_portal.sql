-- NAAC portal migration. Uses prefixed tables; does not alter existing application tables.
create table public.naac_departments(name text primary key,created_at timestamptz not null default now());
insert into public.naac_departments(name) values ('Electrical Engineering'),('Computer Science & Engineering'),('Mechanical Engineering'),('Textile Technology');
create table public.naac_members(email text primary key,user_id uuid unique references auth.users(id),name text not null,role text not null default 'respondent' check(role in ('respondent','coordinator','admin')),department text references public.naac_departments(name),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.naac_panel_definitions(id text primary key,definition jsonb not null);
create table public.naac_submissions(id uuid primary key,created_by uuid not null references auth.users(id),department text not null references public.naac_departments(name),year text not null check(year in ('2023–24','2024–25','2025–26')),panel text not null references public.naac_panel_definitions(id),status text not null check(status in ('Draft','Submitted','Department approved','Approved','Returned')),version integer not null,payload jsonb not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index naac_submission_department on public.naac_submissions(department,year,panel);
create index naac_submission_owner on public.naac_submissions(created_by);
create table public.naac_evidence(id uuid primary key,submission_id uuid not null references public.naac_submissions(id),object_key text unique not null,payload jsonb not null,created_at timestamptz not null default now(),created_by uuid not null references auth.users(id));
create index naac_evidence_submission on public.naac_evidence(submission_id);
create table public.naac_revisions(id uuid primary key default gen_random_uuid(),submission_id uuid not null references public.naac_submissions(id),payload jsonb not null,created_at timestamptz not null default now(),created_by uuid not null references auth.users(id));
create table public.naac_reviews(id uuid primary key default gen_random_uuid(),submission_id uuid not null references public.naac_submissions(id),decision text not null,comments text not null,created_at timestamptz not null default now(),created_by uuid not null references auth.users(id));
create table public.naac_reports(id uuid primary key,department text,payload jsonb not null,created_at timestamptz not null default now(),created_by uuid not null references auth.users(id));
create table public.naac_audit(id uuid primary key default gen_random_uuid(),action text not null,entity_id text not null,created_at timestamptz not null default now(),created_by uuid not null references auth.users(id));
alter table public.naac_departments enable row level security;
alter table public.naac_members enable row level security;
alter table public.naac_panel_definitions enable row level security;
alter table public.naac_submissions enable row level security;
alter table public.naac_evidence enable row level security;
alter table public.naac_revisions enable row level security;
alter table public.naac_reviews enable row level security;
alter table public.naac_reports enable row level security;
alter table public.naac_audit enable row level security;

create function public.naac_role() returns text language sql stable security definer set search_path='' as $$ select role from public.naac_members where user_id=auth.uid() $$;
create function public.naac_department() returns text language sql stable security definer set search_path='' as $$ select department from public.naac_members where user_id=auth.uid() $$;
create function public.naac_can_read(record_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.naac_submissions s where s.id=record_id and (public.naac_role()='admin' or (public.naac_role()='coordinator' and s.department=public.naac_department()) or s.created_by=auth.uid()))
$$;
create function public.naac_can_upload(record_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.naac_submissions s where s.id=record_id and s.status in ('Draft','Returned') and (public.naac_role()='admin' or s.created_by=auth.uid()))
$$;
create policy naac_departments_read on public.naac_departments for select to authenticated using(true);
create policy naac_panels_read on public.naac_panel_definitions for select to authenticated using(true);
create policy naac_members_read on public.naac_members for select to authenticated using(user_id=auth.uid() or public.naac_role()='admin');
create policy naac_submissions_read on public.naac_submissions for select to authenticated using(public.naac_can_read(id));
create policy naac_evidence_read on public.naac_evidence for select to authenticated using(public.naac_can_read(submission_id));
create policy naac_revisions_read on public.naac_revisions for select to authenticated using(public.naac_can_read(submission_id));
create policy naac_reviews_read on public.naac_reviews for select to authenticated using(public.naac_can_read(submission_id));
create policy naac_reports_read on public.naac_reports for select to authenticated using(public.naac_role()='admin' or created_by=auth.uid());
create policy naac_audit_read on public.naac_audit for select to authenticated using(public.naac_role()='admin');
revoke all on public.naac_departments,public.naac_members,public.naac_panel_definitions,public.naac_submissions,public.naac_evidence,public.naac_revisions,public.naac_reviews,public.naac_reports,public.naac_audit from anon,authenticated;
grant select on public.naac_departments,public.naac_members,public.naac_panel_definitions,public.naac_submissions,public.naac_evidence,public.naac_revisions,public.naac_reviews,public.naac_reports,public.naac_audit to authenticated;

insert into storage.buckets(id,name,public,file_size_limit) values('naac-evidence','naac-evidence',false,20971520) on conflict(id) do nothing;
do $$ begin if exists(select 1 from storage.buckets where id='naac-evidence' and public) then raise exception 'Existing naac-evidence bucket is public. Resolve the name collision before applying this migration.';end if;end $$;
create policy naac_storage_insert on storage.objects for insert to authenticated with check(bucket_id='naac-evidence' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}$' and public.naac_can_upload((storage.foldername(name))[1]::uuid));
create policy naac_storage_read on storage.objects for select to authenticated using(bucket_id='naac-evidence' and exists(select 1 from public.naac_evidence e where e.object_key=name and public.naac_can_read(e.submission_id)));
-- No update/delete policies: uploaded originals cannot be overwritten or deleted by portal clients.

create function public.naac_missing(item jsonb) returns text[] language plpgsql stable security definer set search_path='' as $$
declare result text[]='{}';k text;f jsonb;v jsonb;begin
 foreach k in array array['year','department','respondent','designation','email','date'] loop if coalesce(trim(item->>k),'')='' then result=array_append(result,k);end if;end loop;
 for f in select jsonb_array_elements(definition->'fields') from public.naac_panel_definitions where id=item->>'panel' loop
 if coalesce((f->>'required')::boolean,false) and (not(f?'when') or item->'data'->>(f->'when'->>0)=f->'when'->>1) then
 v=item->'data'->(f->>'label');if v is null or v='null'::jsonb or v='[]'::jsonb or trim(v#>>'{}')='' then result=array_append(result,f->>'label');end if;end if;end loop;return result;end $$;

create function public.naac_portal(action text,payload jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 insert into public.naac_members(email,user_id,name) values(lower(account.email),uid,coalesce(account.raw_user_meta_data->>'full_name',account.email)) on conflict(email) do update set user_id=excluded.user_id where naac_members.user_id is null or naac_members.user_id=excluded.user_id;
 select * into member from public.naac_members where user_id=uid;
 if member.user_id is null then raise exception 'Account membership could not be established.';end if;
 if action='load' then
 return jsonb_build_object('user',jsonb_build_object('email',member.email,'name',member.name,'role',member.role,'department',coalesce(member.department,'')),
 'departments',(select coalesce(jsonb_agg(name order by name),'[]') from public.naac_departments),
 'entries',(select coalesce(jsonb_agg(payload order by updated_at desc),'[]') from public.naac_submissions where public.naac_can_read(id)),
 'evidence',(select coalesce(jsonb_agg(payload),'[]') from public.naac_evidence where public.naac_can_read(submission_id)),
 'reports',(select coalesce(jsonb_agg(payload order by created_at desc),'[]') from public.naac_reports where member.role='admin' or created_by=uid),
 'users',(select coalesce(jsonb_agg(jsonb_build_object('email',email,'name',name,'role',role,'department',department)),'[]') from public.naac_members where member.role='admin'),
 'audit',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from (select a.id,a.action,a.entity_id,a.created_at,m.email as created_by from public.naac_audit a join public.naac_members m on m.user_id=a.created_by where member.role='admin' order by a.created_at desc limit 200) a));
 end if;
 if action='onboard' then
 if member.role<>'respondent' or member.department is not null then raise exception 'Ask an administrator to change an existing department.';end if;
 if not exists(select 1 from public.naac_departments where name=payload->>'department') or coalesce(trim(payload->>'name'),'')='' then raise exception 'Enter your name and select a valid department.';end if;
 update public.naac_members set name=left(payload->>'name',200),department=payload->>'department',updated_at=t where user_id=uid;
 elsif action='department' then
 if member.role<>'admin' then raise exception 'Administrator access required.' using errcode='42501';end if;
 if coalesce(trim(payload->>'name'),'')='' or length(payload->>'name')>120 then raise exception 'Enter a department name up to 120 characters.';end if;
 insert into public.naac_departments(name) values(trim(payload->>'name'));
 elsif action='user' then
 if member.role<>'admin' then raise exception 'Administrator access required.' using errcode='42501';end if;
 role_value=payload->>'role';if role_value not in ('admin','coordinator','respondent') or coalesce(payload->>'email','')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Enter a valid email and role.';end if;
 if lower(payload->>'email')=member.email and role_value<>'admin' then raise exception 'You cannot remove your own administrator access.';end if;
 if role_value<>'admin' and not exists(select 1 from public.naac_departments where name=payload->>'department') then raise exception 'Select a valid department.';end if;
 insert into public.naac_members(email,name,role,department) values(lower(payload->>'email'),left(coalesce(nullif(payload->>'name',''),payload->>'email'),200),role_value,case when role_value='admin' then null else payload->>'department' end)
 on conflict(email) do update set name=excluded.name,role=excluded.role,department=excluded.department,updated_at=t;
 elsif action in ('save','submit') then
 raw=payload->'entry';select d.definition into definition from public.naac_panel_definitions d where id=raw->>'panel';
 if definition is null or raw->>'year' not in ('2023–24','2024–25','2025–26') then raise exception 'Select a valid annexure and academic year.';end if;
 if member.role<>'admin' and (member.department is null or member.department<>raw->>'department') then raise exception 'Select your assigned department.' using errcode='42501';end if;
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
 rid=(payload->>'id')::uuid;if not public.naac_can_read(rid) then raise exception 'Access denied.' using errcode='42501';end if;
 return jsonb_build_object('history',(select coalesce(jsonb_agg(jsonb_build_object('payload',r.payload,'created_at',r.created_at,'created_by',m.email) order by r.created_at desc),'[]') from public.naac_revisions r join public.naac_members m on m.user_id=r.created_by where submission_id=rid));
 elsif action='registerEvidence' then
 rid=(payload->>'entryId')::uuid;eid=(payload->>'id')::uuid;select * into old from public.naac_submissions where id=rid for update;
 if not public.naac_can_upload(rid) then raise exception 'Save a draft or return this submission before attaching evidence.' using errcode='42501';end if;
 if payload->>'objectKey'<>rid::text||'/'||eid::text then raise exception 'Invalid object path.';end if;
 select metadata into object_meta from storage.objects where bucket_id='naac-evidence' and name=payload->>'objectKey' and owner_id=uid::text;
 if object_meta is null then raise exception 'Upload the original file first.';end if;
 if (object_meta->>'size')::bigint<> (payload->>'size')::bigint or (payload->>'size')::bigint not between 1 and 20971520 then raise exception 'Invalid file size.';end if;
 if payload->>'name'!~*'\.(pdf|docx?|xlsx?|csv|pptx?|png|jpe?g|webp|txt)$' then raise exception 'Unsupported file extension.';end if;
 select d.definition into definition from public.naac_panel_definitions d where id=old.panel;
 if not(definition->'evidence' @> jsonb_build_array(payload->>'type')) then raise exception 'Invalid document type.';end if;
 item=jsonb_build_object('id',eid,'entryId',rid,'name',left(payload->>'name',255),'type',payload->>'type','size',(payload->>'size')::bigint,'year',old.year,'department',old.department,'parameter',old.panel,'activity',coalesce(old.payload->'data'->>'Title of the project',old.payload->'data'->>'Seminar topic',old.payload->'data'->>(definition->'fields'->0->>'label'),'Record'),'uploadedBy',member.email,'uploadedAt',t,'status','Unverified','comments','');
 insert into public.naac_evidence values(eid,rid,payload->>'objectKey',item,t,uid);result=jsonb_build_object('evidence',item);
 elsif action='evidenceDownload' then
 select * into document from public.naac_evidence where id=(payload->>'id')::uuid;
 if document.id is null or not public.naac_can_read(document.submission_id) then raise exception 'Document not found.' using errcode='42501';end if;
 return jsonb_build_object('objectKey',document.object_key,'name',document.payload->>'name');
 elsif action='verifyEvidence' then
 select * into document from public.naac_evidence where id=(payload->>'id')::uuid for update;select * into old from public.naac_submissions where id=document.submission_id;
 if document.id is null or not(member.role='admin' or member.role='coordinator' and old.department=member.department) then raise exception 'Coordinator access required.' using errcode='42501';end if;
 if payload->>'status' not in ('Verified','Unverified','Needs correction') then raise exception 'Invalid evidence status.';end if;
 item=document.payload||jsonb_build_object('status',payload->>'status','comments',left(coalesce(payload->>'comments',''),12000));update public.naac_evidence set payload=item where id=document.id;result=jsonb_build_object('evidence',item);rid=document.submission_id;
 elsif action='review' then
 rid=(payload->>'id')::uuid;select * into old from public.naac_submissions where id=rid for update;
 if old.id is null or not(member.role='admin' or member.role='coordinator' and old.department=member.department) then raise exception 'Coordinator access required.' using errcode='42501';end if;
 newstatus=payload->>'status';if old.status not in ('Submitted','Department approved') or newstatus not in ('Department approved','Approved','Returned') then raise exception 'Invalid review transition.';end if;
 if newstatus='Approved' and member.role<>'admin' then raise exception 'Final approval requires the NAAC coordinator.' using errcode='42501';end if;
 if newstatus='Returned' and coalesce(trim(payload->>'comment'),'')='' then raise exception 'Explain the correction required.';end if;
 if newstatus<>'Returned' and (cardinality(public.naac_missing(old.payload))>0 or not exists(select 1 from public.naac_evidence e where submission_id=rid and e.payload->>'status'='Verified')) then raise exception 'Complete all required information and verify supporting evidence before approval.';end if;
 item=old.payload||jsonb_build_object('status',newstatus,'comment',left(coalesce(payload->>'comment',''),12000),'updatedAt',t,'version',old.version+1);
 update public.naac_submissions set payload=item,status=newstatus,version=version+1,updated_at=t where id=rid;
 insert into public.naac_reviews(submission_id,decision,comments,created_by) values(rid,newstatus,coalesce(payload->>'comment',''),uid);result=jsonb_build_object('entry',item);
 elsif action='createReport' then
 if member.role='respondent' then raise exception 'Coordinator access required.' using errcode='42501';end if;
 raw=payload->'report';rid=gen_random_uuid();data_year=coalesce(raw->>'year','');data_department=case when member.role='coordinator' then member.department else coalesce(raw->>'department','') end;data_panel=coalesce(raw->>'parameter','');
 select coalesce(jsonb_agg(jsonb_build_object('entry',s.payload,'evidence',(select coalesce(jsonb_agg(e.payload),'[]') from public.naac_evidence e where e.submission_id=s.id))),'[]') into snapshot from public.naac_submissions s where public.naac_can_read(s.id) and s.status in ('Submitted','Department approved','Approved') and (data_year='' or s.year=data_year) and (data_department='' or s.department=data_department) and (data_panel='' or s.panel=data_panel);
 -- Fail on concurrent changes instead of attaching sources newer than those summarized.
 if exists(select 1 from jsonb_array_elements(snapshot) s where not exists(select 1 from jsonb_array_elements(raw->'sourceSnapshots') supplied where supplied->'entry'=s->'entry' and supplied->'evidence' @> s->'evidence' and supplied->'evidence' <@ s->'evidence')) or jsonb_array_length(snapshot)<>jsonb_array_length(raw->'sourceSnapshots') then raise exception 'Source records changed while summarizing. Generate the report again.';end if;
 sections=raw->'sections';if jsonb_typeof(sections)<>'array' then raise exception 'Invalid report sections.';end if;
 for f in select jsonb_array_elements(sections) loop
 if jsonb_typeof(f->'text')<>'string' or jsonb_typeof(f->'heading')<>'string' or jsonb_typeof(f->'sources')<>'array' then raise exception 'Invalid report section.';end if;
 if exists(select 1 from jsonb_array_elements_text(f->'sources') sid where not exists(select 1 from jsonb_array_elements(snapshot) s where s->'entry'->>'id'=sid)) then raise exception 'Unknown report source.';end if;
 end loop;
 item=jsonb_build_object('id',rid,'title','NAAC Point-5 Consolidated Report','year',data_year,'department',data_department,'parameter',data_panel,'mode',case when raw->>'mode'='AI-generated' then 'AI-generated' else 'Count-based' end,'status','Draft','sections',sections,'createdAt',t,'createdBy',member.email,'version',1,'sourceSnapshots',snapshot);
 insert into public.naac_reports values(rid,nullif(data_department,''),item,t,uid);result=jsonb_build_object('report',item);
 elsif action='updateReport' then
 raw=payload->'report';rid=(raw->>'id')::uuid;select * into report from public.naac_reports where id=rid for update;
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
 insert into public.naac_audit(action,entity_id,created_by) values(action,coalesce(rid::text,payload->>'email',payload->>'name',uid::text),uid);
 return coalesce(result,jsonb_build_object('ok',true));
end $$;
revoke all on function public.naac_portal(text,jsonb),public.naac_missing(jsonb),public.naac_role(),public.naac_department(),public.naac_can_read(uuid),public.naac_can_upload(uuid) from public,anon;
grant execute on function public.naac_portal(text,jsonb),public.naac_role(),public.naac_department(),public.naac_can_read(uuid),public.naac_can_upload(uuid) to authenticated;

-- First administrator; linked to the Google account on first sign-in.
insert into public.naac_members(email,name,role) values('adrijag22@gmail.com','Administrator','admin') on conflict(email) do update set role='admin';
