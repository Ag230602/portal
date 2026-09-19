-- Run with supabase db query --linked --file tests/mechanical-access.sql.
-- Synthetic identities, 151 approvals, records and permission checks all roll back.
begin;
create temporary table access_test_context(owner_id uuid,student_id uuid,other_id uuid,record_id uuid,draft_id uuid);
insert into access_test_context select user_id,gen_random_uuid(),gen_random_uuid(),null,null from public.naac_owner;
grant select,update on access_test_context to authenticated;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select student_id,'naac-access-test-1@example.invalid',now(),'{"full_name":"Mechanical test student"}'::jsonb from access_test_context
union all select other_id,'naac-access-test-2@example.invalid',now(),'{"full_name":"Unapproved test student","role":"admin"}'::jsonb from access_test_context;
insert into auth.identities(user_id,provider,provider_id,identity_data)
select id,'google',id::text,jsonb_build_object('sub',id::text,'email',email) from auth.users where id in(select student_id from access_test_context union all select other_id from access_test_context);
-- A historical report created by a student must still remain owner-only.
insert into public.naac_reports(id,department,payload,created_by)
select gen_random_uuid(),'Mechanical Engineering','{"title":"Private report regression fixture"}'::jsonb,student_id from access_test_context;
set local role authenticated;
do $$
declare state jsonb;saved jsonb;draft jsonb;emails jsonb;owner_uid uuid;student_uid uuid;other_uid uuid;operation text;
begin
 select owner_id,student_id,other_id into owner_uid,student_uid,other_uid from access_test_context;
 perform set_config('request.jwt.claim.sub',student_uid::text,true);
 state=public.naac_portal('load','{}');
 assert state->'user'->>'approved'='false','New accounts must not be approved';
 assert state->'entries'='[]' and state->'reports'='[]' and state->'users'='[]' and state->'audit'='[]','Pending account data leak';
 begin perform public.naac_portal('onboard','{"name":"Fake","department":"Mechanical Engineering"}');raise exception 'Self-enrollment accepted';exception when insufficient_privilege then null;end;
 begin perform public.naac_portal('save','{"entry":{}}');raise exception 'Pending student saved a form';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',owner_uid::text,true);
 select jsonb_agg('naac-access-test-'||i||'@example.invalid') into emails from generate_series(1,151) i;
 state=public.naac_portal('approveStudents',jsonb_build_object('emails',emails));
 assert (state->>'approved')::integer=151,'Bulk approval must support more than 100 students';
 assert (select count(*) from public.naac_members where email like 'naac-access-test-%@example.invalid' and approved)=151,'Enrollment was capped';
 begin perform public.naac_portal('approveStudents','{"emails":["good@example.invalid","invalid-email"]}');raise exception 'Invalid email accepted';exception when raise_exception then if sqlerrm='Invalid email accepted' then raise;end if;end;
 assert not exists(select 1 from public.naac_members where email='good@example.invalid'),'Invalid batch must be atomic';
 perform set_config('request.jwt.claim.sub',student_uid::text,true);
 state=public.naac_portal('load','{}');assert state->'user'->>'approved'='true','Approved student cannot enter';
 saved=jsonb_build_object('entry',jsonb_build_object('id','','panel','5.1','year','2025–26','department','Mechanical Engineering','respondent','Test student','designation','Student','email','spoof@example.invalid','date',current_date::text,'data',jsonb_build_object('Name of Project guide','Guide','Name of students','Test','Title of the project','Mechanical test','Broader subject area covered','Engineering'),'version',0));
 draft=public.naac_portal('save',saved);
 assert draft->'entry'->>'email'='naac-access-test-1@example.invalid','Student identity email spoofed';
 update access_test_context set record_id=(draft->'entry'->>'id')::uuid;
 assert (select count(*) from public.naac_submissions)=1,'Student should only see own draft';
 begin perform public.naac_portal('save',jsonb_set(saved,'{entry,department}','"Electrical Engineering"'));raise exception 'Other department accepted';exception when insufficient_privilege then null;end;
 begin perform public.naac_portal('save',saved#-'{entry,department}');raise exception 'Missing department accepted';exception when insufficient_privilege then null;end;
 foreach operation in array array['approveStudents','user','revokeStudent','backup','history','review','verifyEvidence','createReport','updateReport'] loop
 begin perform public.naac_portal(operation,'{}');raise exception 'Privileged action allowed: %',operation;exception when insufficient_privilege then null;end;
 end loop;
 perform public.naac_portal('submit',draft);
 state=public.naac_portal('load','{}');
 assert state->'entries'='[]' and state->'reports'='[]' and state->'users'='[]' and state->'audit'='[]','Submitted responses or owner data leaked';
 assert (select count(*) from public.naac_submissions)=0,'Direct submitted-response RLS leaked';
 assert (select count(*) from public.naac_revisions)=0,'Direct revision RLS leaked';
 assert (select count(*) from public.naac_reports)=0,'Direct report RLS leaked';
 assert (select count(*) from public.naac_audit)=0,'Direct audit RLS leaked';
 state=public.naac_portal('save',jsonb_set(jsonb_set(saved,'{entry,panel}','"5.3"'),'{entry,data}','{"Number of participating students":"151"}'));
 assert state->'entry'->'data'->>'Number of participating students'='151','Student count capped at 100';
 draft=public.naac_portal('save',saved);update access_test_context set draft_id=(draft->'entry'->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',other_uid::text,true);
 state=public.naac_portal('load','{}');assert state->'user'->>'role'='respondent','Metadata role escalation';
 assert (select count(*) from public.naac_submissions)=0,'Another student draft leaked';
 assert not public.naac_can_upload((select draft_id from access_test_context)),'Another student can upload';
 perform set_config('request.jwt.claim.sub',owner_uid::text,true);
 state=public.naac_portal('load','{}');assert state->'user'->>'role'='admin','Owner lost access';
 assert exists(select 1 from jsonb_array_elements(state->'entries') e where e->>'id'=(select record_id::text from access_test_context)),'Owner cannot see response';
 assert (select count(*) from public.naac_revisions where submission_id=(select record_id from access_test_context))=1,'Owner lost preserved response';
 perform public.naac_portal('revokeStudent','{"email":"naac-access-test-1@example.invalid"}');
 perform set_config('request.jwt.claim.sub',student_uid::text,true);
 state=public.naac_portal('load','{}');assert state->'user'->>'approved'='false','Revocation failed';
 assert (select count(*) from public.naac_submissions)=0,'Revoked student can read drafts';
 assert not public.naac_can_upload((select draft_id from access_test_context)),'Revoked student can upload';
 begin perform public.naac_portal('save',draft);raise exception 'Revoked student saved form';exception when insufficient_privilege then null;end;
end $$;
select 'PASS: 151 approvals, forms-only access, owner privacy, department enforcement, anti-escalation, revocation, direct table RLS' as result;
rollback;
