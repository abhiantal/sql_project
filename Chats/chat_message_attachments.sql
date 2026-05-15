-- ============================================================
-- 📁 FILE 23: CHAT MESSAGE ATTACHMENTS TABLE
-- Media files linked to messages (images, videos, docs, etc.)
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.chat_message_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,

    -- Type
    type TEXT NOT NULL CHECK (type IN (
        'image', 'video', 'audio', 'voice', 'document'
    )),

    -- File info
    url TEXT NOT NULL,
    thumbnail_url TEXT,
    file_name TEXT,
    file_size BIGINT,
    mime_type TEXT,

    -- Dimensions / duration
    width INTEGER,
    height INTEGER,
    duration INTEGER,

    -- Order (multiple attachments per message)
    sort_order INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_chat_attachments_message ON public.chat_message_attachments(message_id);
CREATE INDEX IF NOT EXISTS idx_chat_attachments_chat ON public.chat_message_attachments(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_attachments_type ON public.chat_message_attachments(type);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.chat_message_attachments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS "chat_attachments_sender_all" ON public.chat_message_attachments;
    CREATE POLICY "chat_attachments_sender_all" ON public.chat_message_attachments
        FOR ALL
        USING (
            EXISTS (
                SELECT 1 FROM public.chat_messages
                WHERE chat_messages.id = chat_message_attachments.message_id
                  AND chat_messages.sender_id = auth.uid()
            )
        )
        WITH CHECK (
            EXISTS (
                SELECT 1 FROM public.chat_messages
                WHERE chat_messages.id = chat_message_attachments.message_id
                  AND chat_messages.sender_id = auth.uid()
            )
        );

    DROP POLICY IF EXISTS "chat_attachments_member_select" ON public.chat_message_attachments;
    CREATE POLICY "chat_attachments_member_select" ON public.chat_message_attachments
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM public.chat_messages cm
                JOIN public.chat_members mb ON mb.chat_id = cm.chat_id
                WHERE cm.id = chat_message_attachments.message_id
                  AND mb.user_id = auth.uid()
                  AND mb.is_active = true
            )
        );
END $$;

-- ============================================================
-- FUNCTION: Auto-populate chat_id from message
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_attachment_chat_id()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.chat_id IS NULL THEN
        SELECT chat_id INTO NEW.chat_id
        FROM public.chat_messages
        WHERE id = NEW.message_id;
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================
-- FUNCTION: Get media gallery for chat
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_chat_media_gallery(
    p_chat_id UUID,
    p_user_id UUID,
    p_type TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    message_id UUID,
    type TEXT,
    url TEXT,
    thumbnail_url TEXT,
    file_name TEXT,
    width INTEGER,
    height INTEGER,
    duration INTEGER,
    created_at TIMESTAMPTZ
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate membership
    IF NOT EXISTS(
        SELECT 1 FROM public.chat_members
        WHERE chat_members.chat_id = p_chat_id AND user_id = p_user_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'You are not a member of this chat';
    END IF;

    RETURN QUERY
    SELECT
        a.id, a.message_id, a.type, a.url, a.thumbnail_url,
        a.file_name, a.width, a.height, a.duration, a.created_at
    FROM public.chat_message_attachments a
    JOIN public.chat_messages m ON m.id = a.message_id
    WHERE m.chat_id = p_chat_id
      AND m.is_deleted = false
      AND (p_type IS NULL OR a.type = p_type)
    ORDER BY a.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================
-- TRIGGER: Auto-set chat_id
-- ============================================================
DO $$
BEGIN
    DROP TRIGGER IF EXISTS trigger_set_attachment_chat_id ON public.chat_message_attachments;
    CREATE TRIGGER trigger_set_attachment_chat_id
        BEFORE INSERT ON public.chat_message_attachments
        FOR EACH ROW EXECUTE FUNCTION public.set_attachment_chat_id();
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT ALL ON TABLE public.chat_message_attachments TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_attachment_chat_id() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.get_chat_media_gallery(UUID, UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.chat_message_attachments table ready';
    RAISE NOTICE '   - 1 trigger: trigger_set_attachment_chat_id';
    RAISE NOTICE '   - 2 functions:';
    RAISE NOTICE '     • set_attachment_chat_id()';
    RAISE NOTICE '     • get_chat_media_gallery()';
    RAISE NOTICE '   - 2 RLS policies';
    RAISE NOTICE '   - 3 indexes';
END $$;