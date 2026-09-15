-- Run once in a NEW Supabase project. Existing operator project is not required.
create extension if not exists pgcrypto;
create table public.factory_members (user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.factory_members enable row level security;
create policy own_membership on public.factory_members for select to authenticated using(user_id=auth.uid());
create function public.is_factory_member() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.factory_members where user_id=auth.uid());
$$;
revoke all on function public.is_factory_member() from public;
grant execute on function public.is_factory_member() to authenticated;

create table public.sources (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null default auth.uid() references auth.users(id),
 name text not null check(length(name) between 1 and 120), feed_url text not null check(feed_url like 'https://%'),
 enabled boolean not null default false, last_checked timestamptz, last_error text,
 created_at timestamptz not null default now(), unique(owner_id,feed_url)
);
create table public.articles (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null default auth.uid() references auth.users(id),
 title text not null check(length(title) between 1 and 300), source_name text not null,
 source_url text not null check(source_url like 'https://%'), body text not null check(length(body) between 300 and 20000),
 published_at timestamptz not null, fingerprint text not null,
 score integer not null default 0 check(score between 0 and 100),
 created_at timestamptz not null default now(), unique(owner_id,fingerprint)
);
create table public.assets (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null default auth.uid() references auth.users(id),
 name text not null, storage_path text not null, rights_confirmed boolean not null check(rights_confirmed=true),
 created_at timestamptz not null default now(), check(storage_path like owner_id::text || '/%')
);
create table public.jobs (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null default auth.uid() references auth.users(id),
 kind text not null check(kind in ('scan','produce')), article_id uuid references public.articles(id),
 asset_id uuid references public.assets(id), auto_produce boolean not null default false,
 voice text not null default 'alloy' check(voice in ('alloy','coral','onyx','nova')),
 status text not null default 'queued' check(status in ('queued','running','completed','failed')),
 stage text not null default 'queued', result jsonb, error text,
 started_at timestamptz, finished_at timestamptz, created_at timestamptz not null default now(),
 check(kind <> 'produce' or (article_id is not null and asset_id is not null)),
 check(not auto_produce or asset_id is not null)
);
create unique index one_active_video on public.jobs(owner_id,article_id) where kind='produce' and status in ('queued','running');
create unique index one_active_scan on public.jobs(owner_id) where kind='scan' and status in ('queued','running');
create index queue_order on public.jobs(status,created_at);
create table public.renders (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
 job_id uuid not null unique references public.jobs(id), article_id uuid not null references public.articles(id),
 title text not null, script jsonb not null, storage_path text not null,
 duration_seconds numeric not null, created_at timestamptz not null default now()
);
-- Ownership references must belong to the caller, even though IDs are guess-resistant.
create function public.validate_job() returns trigger language plpgsql set search_path=public as $$
begin
 if new.article_id is not null and not exists(select 1 from public.articles where id=new.article_id and owner_id=new.owner_id) then raise exception 'Article owner mismatch'; end if;
 if new.asset_id is not null and not exists(select 1 from public.assets where id=new.asset_id and owner_id=new.owner_id) then raise exception 'Asset owner mismatch'; end if;
 return new;
end $$;
create trigger job_ownership before insert on public.jobs for each row execute function public.validate_job();

alter table public.sources enable row level security;
alter table public.articles enable row level security;
alter table public.assets enable row level security;
alter table public.jobs enable row level security;
alter table public.renders enable row level security;
create policy sources_read on public.sources for select to authenticated using(owner_id=auth.uid() and public.is_factory_member());
create policy sources_add on public.sources for insert to authenticated with check(owner_id=auth.uid() and public.is_factory_member());
create policy sources_edit on public.sources for update to authenticated using(owner_id=auth.uid() and public.is_factory_member()) with check(owner_id=auth.uid());
create policy articles_read on public.articles for select to authenticated using(owner_id=auth.uid() and public.is_factory_member());
create policy articles_add on public.articles for insert to authenticated with check(owner_id=auth.uid() and public.is_factory_member());
create policy assets_read on public.assets for select to authenticated using(owner_id=auth.uid() and public.is_factory_member());
create policy assets_add on public.assets for insert to authenticated with check(owner_id=auth.uid() and public.is_factory_member());
create policy jobs_read on public.jobs for select to authenticated using(owner_id=auth.uid() and public.is_factory_member());
create policy jobs_add on public.jobs for insert to authenticated with check(owner_id=auth.uid() and public.is_factory_member() and status='queued' and stage='queued' and result is null and error is null and started_at is null and finished_at is null);
create policy renders_read on public.renders for select to authenticated using(owner_id=auth.uid() and public.is_factory_member());
-- Explicit least-privilege grants: clients cannot mark jobs complete or forge renders.
revoke all on public.factory_members,public.sources,public.articles,public.assets,public.jobs,public.renders from anon,authenticated;
grant select on public.factory_members,public.sources,public.articles,public.assets,public.jobs,public.renders to authenticated;
grant insert on public.sources,public.articles,public.assets,public.jobs to authenticated;
grant update(name,feed_url,enabled) on public.sources to authenticated;
grant all on public.factory_members,public.sources,public.articles,public.assets,public.jobs,public.renders to service_role;

-- Atomic claim prevents two workers rendering the same queued job.
create function public.claim_factory_job(p_owner uuid) returns setof public.jobs language plpgsql security definer set search_path=public as $$
begin
 perform pg_advisory_xact_lock(hashtext(p_owner::text));
 -- Serialise jobs per owner, including across separate worker containers.
 if exists(select 1 from public.jobs where owner_id=p_owner and status='running') then return; end if;
 return query update public.jobs set status='running',stage='starting',started_at=now()
 where id=(select id from public.jobs where owner_id=p_owner and status='queued' order by created_at for update skip locked limit 1)
 returning *;
end $$;
revoke all on function public.claim_factory_job(uuid) from public,anon,authenticated;
grant execute on function public.claim_factory_job(uuid) to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('gameplay','gameplay',false,52428800,array['video/mp4']),
 ('renders','renders',false,209715200,array['video/mp4']) on conflict(id) do nothing;
create policy gameplay_upload on storage.objects for insert to authenticated with check(bucket_id='gameplay' and (storage.foldername(name))[1]=auth.uid()::text and public.is_factory_member());
create policy factory_storage_read on storage.objects for select to authenticated using(bucket_id in ('gameplay','renders') and (storage.foldername(name))[1]=auth.uid()::text and public.is_factory_member());
