begin;
create temporary table naac_diagnosis(result text, sqlstate text, detail text) on commit drop;
grant select,insert on naac_diagnosis to authenticated;
do $$ declare u uuid;begin select user_id into u from public.naac_owner limit 1;perform set_config('request.jwt.claim.sub',u::text,true);end $$;
set local role authenticated;
do $$ declare data jsonb;code text;message text;begin
 begin
  data=public.naac_portal('load','{}');
  insert into naac_diagnosis values('Authenticated workspace load passed','00000','role='||(data->'user'->>'role')||'; expected collections='||((jsonb_typeof(data->'entries')='array' and jsonb_typeof(data->'evidence')='array' and jsonb_typeof(data->'reports')='array')::text));
 exception when others then get stacked diagnostics code=returned_sqlstate,message=message_text;insert into naac_diagnosis values('Authenticated workspace load failed',code,message);end;
 perform set_config('request.jwt.claim.sub','',true);
 begin
  data=public.naac_portal('load','{}');insert into naac_diagnosis values('FAIL: missing identity accepted','','');
 exception when others then get stacked diagnostics code=returned_sqlstate;insert into naac_diagnosis values('Missing identity rejected',code,'');end;
end $$;
select * from naac_diagnosis;
rollback;

-- Requires one existing Google identity. All test records are rolled back.
begin;
do $$ declare u uuid;begin select user_id into u from public.naac_owner limit 1;perform set_config('request.jwt.claim.sub',u::text,true);end $$;
set local role authenticated;
do $$
declare state jsonb;entry jsonb;saved jsonb;history jsonb;
begin
 state=public.naac_portal('load','{}');
 entry=jsonb_build_object('id','','panel','5.1','year','2025–26','department',coalesce(nullif(state->'user'->>'department',''),'Mechanical Engineering'),'respondent','Rollback regression check','designation','Test faculty','email',state->'user'->>'email','date',current_date::text,'data',jsonb_build_object('Name of Project guide','Test guide','Name of students','Synthetic regression student','Title of the project','Rollback regression project','Broader subject area covered','Test subject'),'version',0);
 saved=public.naac_portal('save',jsonb_build_object('entry',entry));
 saved=public.naac_portal('submit',jsonb_build_object('entry',saved->'entry'));
 if saved->'entry'->>'status'<>'Submitted' then raise exception 'Submission status regression';end if;
 history=public.naac_portal('history',jsonb_build_object('id',saved->'entry'->>'id'));
 if jsonb_array_length(history->'history')<>1 then raise exception 'Submission snapshot regression';end if;
 state=public.naac_portal('load','{}');
 if not exists(select 1 from jsonb_array_elements(state->'entries') e where e->>'id'=saved->'entry'->>'id') then raise exception 'Saved record visibility regression';end if;
end $$;
select 'PASS: draft save, submission, immutable snapshot and workspace reload' as result;
rollback;
