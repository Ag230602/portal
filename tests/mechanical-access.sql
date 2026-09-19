-- Run with supabase db query --linked --file tests/mechanical-access.sql.
-- Synthetic identities, 151 Google sign-ins, records and permission checks all roll back.
begin;
create temporary table access_test_context(owner_id uuid,student_id uuid,other_id uuid,record_id uuid,draft_id uuid);
insert into access_test_context select user_id,gen_random_uuid(),gen_random_uuid(),null,null from public.naac_owner;
grant select,update on access_test_context to authenticated;
create temporary table access_test_students as
select student_id as id,'naac-access-test-1@example.invalid'::text as email from access_test_context
union all select other_id,'naac-access-test-2@example.invalid' from access_test_context
union all select gen_random_uuid(),'naac-access-test-'||i||'@example.invalid' from generate_series(3,151) i;
grant select on access_test_students to authenticated;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select id,email,now(),'{"full_name":"Test respondent","role":"admin"}'::jsonb from access_test_students;
insert into auth.identities(user_id,provider,provider_id,identity_data)
select id,'google',id::text,jsonb_build_object('sub',id::text,'email',email) from access_test_students;
-- A historical report created by a student must still remain owner-only.
insert into public.naac_reports(id,department,payload,created_by)
select gen_random_uuid(),'Mechanical Engineering','{"title":"Private report regression fixture"}'::jsonb,student_id from access_test_context;
set local role authenticated;
do $$
declare state jsonb;saved jsonb;draft jsonb;test_user record;owner_uid uuid;student_uid uuid;other_uid uuid;operation text;
begin
 select owner_id,student_id,other_id into owner_uid,student_uid,other_uid from access_test_context;
 -- Every new Google identity gets forms access immediately without approval.
 for test_user in select id from access_test_students loop
 perform set_config('request.jwt.claim.sub',test_user.id::text,true);
 state=public.naac_portal('load','{}');
 assert state->'user'->>'approved'='true','Google account blocked by legacy approval requirement';
 assert state->'user'->>'role'='respondent','Metadata role escalation';
 assert state->'entries'='[]' and state->'reports'='[]' and state->'users'='[]' and state->'audit'='[]','New account data leak';
 end loop;
 perform set_config('request.jwt.claim.sub',owner_uid::text,true);
 assert (select count(*) from public.naac_members where email like 'naac-access-test-%@example.invalid')=151,'Enrollment was capped';
 assert (select count(*) from public.naac_members where email like 'naac-access-test-%@example.invalid' and approved)=0,'Access should not require approving members';
 perform set_config('request.jwt.claim.sub',student_uid::text,true);
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
 -- Legacy flags remain false, but do not gate saving or submission.
 perform set_config('request.jwt.claim.sub',student_uid::text,true);
 state=public.naac_portal('save',draft);
 assert state->'entry'->>'status'='Draft','Unapproved Google account cannot save draft';
end $$;
select 'PASS: 151 sign-ins without approval, form submission, owner privacy, draft isolation, anti-escalation, direct table RLS' as result;
rollback;
