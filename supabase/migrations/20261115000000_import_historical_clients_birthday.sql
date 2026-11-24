-- Phase 1 enhancement: add optional birthday to existing historical CSV import.
-- Apply to DEVELOPMENT ONLY after reviewing.
-- No loan applications, settlement records or marketing consents are created.
-- BrokerRelay: historical client-only CSV import.
-- REVIEW AND APPLY TO DEVELOPMENT ONLY. Does not create loans or settlement events.
-- Privileged RPC: membership and broker profile are validated independently server-side.
create or replace function public.import_historical_clients(
  p_organisation_id uuid,
  p_rows jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_row jsonb;
  v_email text;
  v_mobile text;
  v_first text;
  v_last text;
  v_created uuid;
  v_count int := 0;
  v_duplicate int := 0;
  v_invalid int := 0;
  v_total int;
  v_email_seen text[] := '{}'::text[];
  v_broker uuid;
  v_birthday text;
  v_birthdate date;
  v_birthdays_saved int := 0;
  v_day int;
  v_month int;
  v_year int;
begin
  if v_actor is null or p_organisation_id is null then
    raise exception 'UNAUTHENTICATED' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.organisation_memberships m
    join public.organisations o on o.id = m.organisation_id
    where m.organisation_id = p_organisation_id
      and m.user_id = v_actor
      and m.status = 'active'
      and m.role in ('company_admin', 'broker')
      and o.status = 'active'
  ) or not exists (
    select 1 from public.broker_profiles bp
    where bp.organisation_id = p_organisation_id
      and bp.user_id = v_actor
      and bp.is_active = true
  ) then
    raise exception 'BROKER_NOT_AUTHORISED' using errcode = '42501';
  end if;
  v_broker := v_actor;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'ROWS_MUST_BE_ARRAY' using errcode='22023';
  end if;
  v_total := jsonb_array_length(p_rows);
  if v_total < 1 or v_total > 500 then
    raise exception 'UPLOAD_MUST_HAVE_1_TO_500_ROWS' using errcode='22023';
  end if;
  -- Serialise concurrent imports within one company to avoid duplicate emails.
  perform pg_advisory_xact_lock(hashtextextended(p_organisation_id::text, 0));
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_first := btrim(coalesce(v_row->>'first_name', ''));
    v_last := btrim(coalesce(v_row->>'last_name', ''));
    v_email := lower(btrim(coalesce(v_row->>'email', '')));
    v_mobile := btrim(coalesce(v_row->>'mobile', ''));
    v_birthday := btrim(coalesce(v_row->>'birthday', ''));
    if length(v_first) not between 1 and 120
       or length(v_last) not between 1 and 120
       or length(v_email) > 254
       or v_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$'
       or length(v_mobile) not between 8 and 25
       or v_mobile !~ '^\+?[0-9 ()-]+$' then
      v_invalid := v_invalid + 1;
      continue;
    end if;
    -- Optional birthday uses an unambiguous DD/MM/YYYY input.
    -- The year is validated but deliberately NOT retained: the existing greeting
    -- preferences model stores only month and day.
    v_birthdate := null;
    if v_birthday <> '' then
      if v_birthday !~ '^([0-9]{2})/([0-9]{2})/([0-9]{4})$' then
        v_invalid := v_invalid + 1;
        continue;
      end if;
      v_day := split_part(v_birthday, '/', 1)::int;
      v_month := split_part(v_birthday, '/', 2)::int;
      v_year := split_part(v_birthday, '/', 3)::int;
      if v_year < 1850 or v_year > extract(year from current_date)::int then
        v_invalid := v_invalid + 1;
        continue;
      end if;
      begin
        v_birthdate := make_date(v_year, v_month, v_day);
      exception when datetime_field_overflow or invalid_datetime_format then
        v_invalid := v_invalid + 1;
        continue;
      end;
      if v_birthdate > current_date then
        v_invalid := v_invalid + 1;
        continue;
      end if;
    end if;
    if v_email = any(v_email_seen) or exists (
      select 1 from public.clients c
      where c.organisation_id = p_organisation_id
        and lower(btrim(c.email)) = v_email
    ) then
      v_duplicate := v_duplicate + 1;
      continue;
    end if;
    v_email_seen := array_append(v_email_seen, v_email);
    insert into public.clients
      (organisation_id, first_name, last_name, email, mobile, status, created_by_user_id)
    values
      (p_organisation_id, v_first, v_last, v_email, v_mobile, 'lead', v_actor)
    returning id into v_created;
    insert into public.client_assignments
      (organisation_id, client_id, member_user_id, assignment_role)
    values (p_organisation_id, v_created, v_broker, 'primary_broker');
    if v_birthdate is not null then
      insert into public.client_greeting_preferences
        (client_id, organisation_id, birthday_month, birthday_day,
         birthday_enabled, company_messages_enabled)
      values
        (v_created, p_organisation_id,
         extract(month from v_birthdate)::int,
         extract(day from v_birthdate)::int,
         false, false);
      v_birthdays_saved := v_birthdays_saved + 1;
    end if;
    v_count := v_count + 1;
  end loop;
  insert into public.audit_events
    (organisation_id, actor_user_id, event_type, entity_type, metadata)
  values
    (p_organisation_id, v_actor, 'historical_clients_imported',
     'client_import', jsonb_build_object('received',v_total,'created',v_count,
                                      'duplicates',v_duplicate,'invalid',v_invalid,'birthdays_saved',v_birthdays_saved,
                                      'loan_applications_created',0,'billing_events_created',0));
  return jsonb_build_object('received',v_total,'created',v_count,
                            'duplicates',v_duplicate,'invalid',v_invalid,'birthdays_saved',v_birthdays_saved,
                            'billing_events_created',0);
end;
$$;
revoke all on function public.import_historical_clients(uuid,jsonb) from public, anon;
grant execute on function public.import_historical_clients(uuid,jsonb) to authenticated;
