-- Supabase Realtime feed updates; this does not change Vibe visibility.
do $$
begin
  alter publication supabase_realtime add table public.vibes_statuses;
exception when duplicate_object then
  null;
end;
$$;
