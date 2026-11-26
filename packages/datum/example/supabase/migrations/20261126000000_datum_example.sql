-- Schema for the Datum example app (tasks, paint canvases/strokes, sync metadata).
-- Applied automatically by `supabase start` / `supabase db reset`; paste into the
-- SQL editor for a hosted project. Columns are snake_case versions of each
-- entity's toDatumMap() keys (the adapter converts both ways).

-- Per-user sync metadata (DatumSyncMetadata.toMap()).
CREATE TABLE public.sync_metadata (
    user_id TEXT PRIMARY KEY,
    last_sync_time TEXT,
    last_successful_sync_time TEXT,
    data_hash TEXT,
    device_id TEXT,
    devices JSONB,
    custom_metadata JSONB,
    entity_counts JSONB,
    sync_status TEXT NOT NULL DEFAULT 'pending',
    sync_version INTEGER NOT NULL DEFAULT 0,
    server_timestamp TEXT,
    conflict_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0,
    sync_duration INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.tasks (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    modified_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.paint_canvases (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    thumbnail_stroke_data JSONB,
    stroke_count INTEGER DEFAULT 0,
    is_deleted BOOLEAN DEFAULT FALSE,
    version INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    modified_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.paint_strokes (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    canvas_id TEXT NOT NULL DEFAULT '',
    points JSONB NOT NULL,
    color BIGINT NOT NULL,
    stroke_width REAL NOT NULL,
    "order" INTEGER NOT NULL,
    is_deleted BOOLEAN DEFAULT FALSE,
    version INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    modified_at TIMESTAMPTZ DEFAULT NOW()
);

-- Every table: owner-only access, user index, realtime.
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['sync_metadata', 'tasks', 'paint_canvases', 'paint_strokes'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY "owner only" ON public.%I FOR ALL USING (auth.uid()::text = user_id) WITH CHECK (auth.uid()::text = user_id)', t);
    EXECUTE format('CREATE INDEX ON public.%I (user_id)', t);
    EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
  END LOOP;
END $$;

CREATE INDEX ON public.tasks (modified_at);
CREATE INDEX ON public.paint_canvases (modified_at);
CREATE INDEX ON public.paint_strokes (canvas_id);
CREATE INDEX ON public.paint_strokes (modified_at);
