-- 001_logic_tests.sql
-- Database tests for VITRAX: route privacy trimming, 3-vote hazard clearing,
-- and badge counting / awarding.
--
-- HOW TO RUN: paste the whole file into the Supabase SQL Editor and press Run.
-- You get a table of PASS / FAIL rows. Everything runs inside a transaction
-- that is rolled back at the end, so NO test data is left in your database.
-- (If a FAIL row mentions "could not create test users", tell me the message.)

begin;

create temp table t (name text, ok boolean, detail text) on commit drop;

-- ---------------------------------------------------------------- route trimming
do $$
declare
  route jsonb; r200 jsonb; r500 jsonb; rzero jsonb; first_lat double precision; last_lat double precision;
begin
  -- 21 points walking north, 0.001 degree (about 111 m) apart: about 2.2 km
  select jsonb_agg(jsonb_build_object('lat', 9.6 + g * 0.001, 'lng', 123.85) order by g)
    into route from generate_series(0, 20) g;

  r200 := public.trim_route(route, 200);
  r500 := public.trim_route(route, 500);
  rzero := public.trim_route(route, 0);

  insert into t values ('trim: zone 200 removes points at both ends',
    jsonb_array_length(r200) < 21 and jsonb_array_length(r200) > 0,
    'kept ' || jsonb_array_length(r200) || ' of 21');

  first_lat := (r200->0->>'lat')::double precision;
  last_lat  := (r200->(jsonb_array_length(r200)-1)->>'lat')::double precision;
  insert into t values ('trim: nothing kept within 200 m of the start',
    first_lat >= 9.6 + 200 / 111195.0,
    'first kept lat ' || first_lat);
  insert into t values ('trim: nothing kept within 200 m of the finish',
    last_lat <= 9.62 - 200 / 111195.0,
    'last kept lat ' || last_lat);
  insert into t values ('trim: a bigger zone (500 m) keeps fewer points',
    jsonb_array_length(r500) < jsonb_array_length(r200),
    '500 m keeps ' || jsonb_array_length(r500) || ', 200 m keeps ' || jsonb_array_length(r200));
  insert into t values ('trim: zone 0 returns the whole route',
    jsonb_array_length(rzero) = 21, 'kept ' || jsonb_array_length(rzero));
  insert into t values ('trim: a route too short to share safely returns nothing',
    public.trim_route('[{"lat":9.6,"lng":123.85},{"lat":9.6005,"lng":123.85},{"lat":9.601,"lng":123.85}]'::jsonb, 200) = '[]'::jsonb,
    'about 110 m route, 200 m zone');
  insert into t values ('trim: null route returns an empty list',
    public.trim_route(null, 200) = '[]'::jsonb, '');
exception when others then
  insert into t values ('trim: tests ran without error', false, sqlerrm);
end $$;

-- ------------------------------------------------- users for the next tests
create temp table u (role text primary key, id uuid) on commit drop;

do $$
declare nm text;
begin
  foreach nm in array array['reporter','v1','v2','v3','rider'] loop
    insert into u values (nm, gen_random_uuid());
    insert into auth.users (id, email) select id, 'test_' || nm || '_' || substr(id::text,1,8) || '@vitrax.test' from u where role = nm;
  end loop;
  insert into t values ('setup: created 5 test users', true, '');
exception when others then
  insert into t values ('setup: could not create test users', false, sqlerrm);
end $$;

-- ------------------------------------------------------ 3-vote hazard clearing
do $$
declare
  hid uuid; reporter uuid; a uuid; b uuid; c uuid; still boolean;
begin
  select id into reporter from u where role = 'reporter';
  select id into a from u where role = 'v1';
  select id into b from u where role = 'v2';
  select id into c from u where role = 'v3';

  insert into public.hazards (user_id, type, lat, lng, reported_at, shared)
  values (reporter, 'pothole', 9.65, 123.85, now(), true) returning id into hid;

  insert into public.hazard_clear_confirmations (hazard_id, user_id) values (hid, a);
  select exists (select 1 from public.hazards where id = hid) into still;
  insert into t values ('clear: still active after 1 vote', still, '');

  insert into public.hazard_clear_confirmations (hazard_id, user_id) values (hid, b);
  select exists (select 1 from public.hazards where id = hid) into still;
  insert into t values ('clear: still active after 2 votes', still, '');

  insert into public.hazard_clear_confirmations (hazard_id, user_id) values (hid, c);
  select exists (select 1 from public.hazards where id = hid) into still;
  insert into t values ('clear: removed after 3 distinct votes', not still, '');

  -- the same person cannot vote twice
  declare hid2 uuid; dup_blocked boolean := false;
  begin
    insert into public.hazards (user_id, type, lat, lng, reported_at, shared)
    values (reporter, 'flooding', 9.66, 123.86, now(), true) returning id into hid2;
    insert into public.hazard_clear_confirmations (hazard_id, user_id) values (hid2, a);
    begin
      insert into public.hazard_clear_confirmations (hazard_id, user_id) values (hid2, a);
    exception when unique_violation then dup_blocked := true;
    end;
    insert into t values ('clear: one person cannot vote twice', dup_blocked, '');
  end;
exception when others then
  insert into t values ('clear: tests ran without error', false, sqlerrm);
end $$;

-- ------------------------------------------------------------- badge counting
do $$
declare
  rider uuid; v1 uuid; stats jsonb; vstats jsonb;
begin
  select id into rider from u where role = 'rider';
  select id into v1 from u where role = 'v1';

  -- day -2: real ride, day -1: real ride, today: tiny accidental save (< 0.2 km)
  insert into public.activities (user_id, type, distance_km, duration_seconds, started_at, route)
  values (rider, 'ride', 1.0, 300, now() - interval '2 days', '[]'::jsonb),
         (rider, 'ride', 1.0, 300, now() - interval '1 day',  '[]'::jsonb),
         (rider, 'ride', 0.05, 20, now(),                      '[]'::jsonb);

  stats := public.badge_stats(rider);
  insert into t values ('badges: tiny saves (under 0.2 km) are not counted as activities',
    (stats->>'first_steps')::int = 2, 'first_steps = ' || (stats->>'first_steps'));
  insert into t values ('badges: total distance is floored sum of km',
    (stats->>'distance')::int = 2, 'distance = ' || (stats->>'distance'));
  insert into t values ('badges: streak counts consecutive days with a real activity',
    (stats->>'streak')::int = 2, 'streak = ' || (stats->>'streak'));

  vstats := public.badge_stats(v1);
  insert into t values ('badges: clearing a hazard counts toward Safety Warden',
    (vstats->>'safety_warden')::int >= 1, 'safety_warden = ' || (vstats->>'safety_warden'));
exception when others then
  insert into t values ('badges: stats ran without error', false, sqlerrm);
end $$;

-- ------------------------------------------------------------ badge awarding
do $$
declare
  rider uuid; first_call int; second_call int; stored int;
begin
  select id into rider from u where role = 'rider';
  perform set_config('request.jwt.claims', json_build_object('sub', rider, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', rider::text, true);

  select count(*) into first_call from public.evaluate_my_badges();
  select count(*) into stored from public.user_badges where user_id = rider and badge_key = 'first_steps' and tier = 'bronze';
  select count(*) into second_call from public.evaluate_my_badges();

  insert into t values ('award: server grants the Bronze First Steps badge', stored = 1,
    'newly awarded ' || first_call || ', stored ' || stored);
  insert into t values ('award: asking again does not award it twice', second_call = 0,
    'second call returned ' || second_call);
exception when others then
  insert into t values ('award: tests ran without error', false, sqlerrm);
end $$;

select case when ok then 'PASS' else 'FAIL' end as result, name, detail
from t
order by ok, name;

rollback;
