-- Uses owner-scoped snapshots internally, without outputting response data.
-- All report writes roll back. No AI calls or student records are modified.
begin;
do $$ declare owner_uid uuid;begin
 select user_id into owner_uid from public.naac_owner;
 perform set_config('request.jwt.claim.sub',owner_uid::text,true);
end $$;
set local role authenticated;
do $$
declare state jsonb;snapshots jsonb;sections jsonb;input jsonb;saved jsonb;edited jsonb;mode_name text;source_id text;
begin
 state=public.naac_portal('load','{}');
 select coalesce(jsonb_agg(jsonb_build_object('entry',e,'evidence',(
 select coalesce(jsonb_agg(f),'[]') from jsonb_array_elements(state->'evidence') f where f->>'entryId'=e->>'id'))),'[]') into snapshots
 from jsonb_array_elements(state->'entries') e where e->>'status' in ('Submitted','Department approved','Approved');
 if jsonb_array_length(snapshots)=0 then raise exception 'Test requires at least one submitted record';end if;
 source_id=snapshots->0->'entry'->>'id';
 sections=jsonb_build_array(jsonb_build_object('heading','Persistence regression','text','Rollback-only report persistence check.','sources',jsonb_build_array(source_id)));
 foreach mode_name in array array['Count-based','AI-generated'] loop
 input=jsonb_build_object('report',jsonb_build_object('year','','department','','parameter','','mode',mode_name,'sections',sections,'sourceSnapshots',snapshots));
 saved=public.naac_portal('createReport',input);
 assert saved->'report'->>'mode'=mode_name,'Report mode changed';
 assert (saved->'report'->'sourceSnapshots') @> snapshots and (saved->'report'->'sourceSnapshots') <@ snapshots and jsonb_array_length(saved->'report'->'sourceSnapshots')=jsonb_array_length(snapshots),'Snapshots lost';
 edited=public.naac_portal('updateReport',jsonb_build_object('report',(saved->'report')||jsonb_build_object('status','Approved')));
 assert edited->'report'->>'status'='Approved','Report approval failed';
 end loop;
 begin
 perform public.naac_portal('createReport',jsonb_set(input,'{report,sourceSnapshots,0,entry,version}','-1'));
 raise exception 'Stale snapshot accepted';
 exception when raise_exception then if sqlerrm<>'Source records changed while summarizing. Generate the report again.' then raise;end if;end;
 begin
 perform public.naac_portal('createReport',jsonb_set(input,'{report,sourceSnapshots,0,evidence}','[{"id":"invented-evidence"}]'));
 raise exception 'Changed evidence accepted';
 exception when raise_exception then if sqlerrm<>'Source records changed while summarizing. Generate the report again.' then raise;end if;end;
 begin
 perform public.naac_portal('createReport',input#-'{report,sourceSnapshots}');
 raise exception 'Missing snapshots accepted';
 exception when raise_exception then if sqlerrm<>'Invalid source snapshots.' then raise;end if;end;
end $$;
select 'PASS: count-based and AI report persistence, approval, stale snapshot rejection, changed evidence rejection' as result;
rollback;
