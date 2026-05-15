-- ============================================================
-- 🚀 MASTER NOTIFICATION ENGINE (UNIFIED)
-- Consolidates Chat, Social, and AI notifications into one file.
-- Populates both Push (Queue) and In-App (History) tables.
-- ============================================================

-- 1. NOTIFICATION QUEUE TABLE (Transient Buffer for FCM)
CREATE TABLE IF NOT EXISTS public.notification_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}'::jsonb,
  status TEXT DEFAULT 'pending',
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  processed_at TIMESTAMPTZ
);

-- 2. NOTIFICATION DISPATCH QUEUE (For High-Concurrency Group Processing)
CREATE TABLE IF NOT EXISTS internal.notification_dispatch_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  message_id UUID REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notification_queue_user_status ON public.notification_queue(user_id, status);
CREATE INDEX IF NOT EXISTS idx_dispatch_queue_status ON internal.notification_dispatch_queue(status) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_notification_queue_status ON public.notification_queue(status) WHERE status = 'pending';

-- ============================================================
-- RLS (Resolves 0008_rls_enabled_no_policy)
-- ============================================================
ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    -- Service Role Policy (Internal Processing)
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'notification_queue' AND policyname = 'service_role_all') THEN
        CREATE POLICY "service_role_all" ON public.notification_queue
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;

    -- User Policy (Personal Access)
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'notification_queue' AND policyname = 'user_view_own') THEN
        CREATE POLICY "user_view_own" ON public.notification_queue
            FOR SELECT TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================
-- 1. CHAT MESSAGE TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION internal.handle_new_chat_message_notification()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_recipient_record RECORD;
  v_sender_name TEXT;
  v_chat_type TEXT;
  v_chat_name TEXT;
  v_notification_body TEXT;
BEGIN
  -- Get sender and chat info
  SELECT COALESCE(display_name, username, 'Someone') INTO v_sender_name FROM public.user_profiles WHERE user_id = NEW.sender_id;
  SELECT type, name INTO v_chat_type, v_chat_name FROM public.chats WHERE id = NEW.chat_id;
  
  v_notification_body := CASE 
    WHEN NEW.type = 'text' THEN LEFT(NEW.text_content, 100)
    WHEN NEW.type = 'image' THEN '📷 Image'
    WHEN NEW.type = 'video' THEN '🎥 Video'
    WHEN NEW.type = 'voice' THEN '🎤 Voice message'
    WHEN NEW.type = 'document' THEN '📄 Document'
    ELSE 'New message'
  END;

  -- SCALABILITY FIX: Instead of iterating thousands of members in the main trigger,
  -- we push to a dispatch queue for asynchronous processing by a background worker.
  INSERT INTO internal.notification_dispatch_queue (chat_id, message_id)
  VALUES (NEW.chat_id, NEW.id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_chat_notification ON public.chat_messages;
CREATE TRIGGER trg_chat_notification AFTER INSERT ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION internal.handle_new_chat_message_notification();

-- ============================================================
-- 2. SOCIAL ENGAGEMENT TRIGGERS (LIKE, COMMENT, FOLLOW)
-- ============================================================

-- LIKE TRIGGER
CREATE OR REPLACE FUNCTION internal.notify_on_new_like()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_recipient_id UUID;
  v_liker_name TEXT;
BEGIN
  IF NEW.target_type = 'post' THEN
    SELECT user_id INTO v_recipient_id FROM public.posts WHERE id = NEW.target_id;
  ELSIF NEW.target_type = 'comment' THEN
    SELECT user_id INTO v_recipient_id FROM public.comments WHERE id = NEW.target_id;
  END IF;

  IF v_recipient_id IS NOT NULL AND v_recipient_id != NEW.user_id THEN
    SELECT COALESCE(display_name, username, 'Someone') INTO v_liker_name FROM public.user_profiles WHERE user_id = NEW.user_id;
    
    INSERT INTO public.notification_queue (user_id, type, title, body, data)
    VALUES (v_recipient_id, 'like', '❤️ New Like', v_liker_name || ' liked your ' || NEW.target_type, jsonb_build_object('target_id', NEW.target_id, 'screen', '/notifications', 'type', NEW.target_type));

    PERFORM public.create_notification(v_recipient_id, 'like', '❤️ New Like', v_liker_name || ' liked your ' || NEW.target_type, jsonb_build_object('target_id', NEW.target_id, 'screen', '/notifications', 'type', NEW.target_type));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_new_like ON public.reactions;
CREATE TRIGGER on_new_like AFTER INSERT ON public.reactions FOR EACH ROW EXECUTE FUNCTION internal.notify_on_new_like();

-- COMMENT TRIGGER
CREATE OR REPLACE FUNCTION internal.notify_on_new_comment()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_recipient_id UUID;
  v_commenter_name TEXT;
BEGIN
  IF NEW.parent_comment_id IS NOT NULL THEN
    SELECT user_id INTO v_recipient_id FROM public.comments WHERE id = NEW.parent_comment_id;
  ELSE
    SELECT user_id INTO v_recipient_id FROM public.posts WHERE id = NEW.post_id;
  END IF;

  IF v_recipient_id IS NOT NULL AND v_recipient_id != NEW.user_id THEN
    SELECT COALESCE(display_name, username, 'Someone') INTO v_commenter_name FROM public.user_profiles WHERE user_id = NEW.user_id;

    INSERT INTO public.notification_queue (user_id, type, title, body, data)
    VALUES (v_recipient_id, CASE WHEN NEW.parent_comment_id IS NOT NULL THEN 'reply' ELSE 'comment' END, CASE WHEN NEW.parent_comment_id IS NOT NULL THEN '💬 New Reply' ELSE '💬 New Comment' END, v_commenter_name || ': "' || LEFT(NEW.content, 50) || '"', jsonb_build_object('post_id', NEW.post_id, 'screen', '/notifications'));

    PERFORM public.create_notification(v_recipient_id, CASE WHEN NEW.parent_comment_id IS NOT NULL THEN 'reply' ELSE 'comment' END, CASE WHEN NEW.parent_comment_id IS NOT NULL THEN '💬 New Reply' ELSE '💬 New Comment' END, v_commenter_name || ': "' || LEFT(NEW.content, 50) || '"', jsonb_build_object('post_id', NEW.post_id, 'screen', '/notifications'));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_new_comment ON public.comments;
CREATE TRIGGER on_new_comment AFTER INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION internal.notify_on_new_comment();

-- FOLLOW TRIGGER
CREATE OR REPLACE FUNCTION internal.notify_on_new_follow()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_follower_name TEXT;
BEGIN
  IF NEW.status != 'active' THEN RETURN NEW; END IF;

  SELECT COALESCE(display_name, username, 'Someone') INTO v_follower_name FROM public.user_profiles WHERE user_id = NEW.follower_id;
  
  INSERT INTO public.notification_queue (user_id, type, title, body, data)
  VALUES (NEW.following_id, 'follow', '👤 New Follower', v_follower_name || ' started following you', jsonb_build_object('follower_id', NEW.follower_id, 'screen', '/notifications'));

  PERFORM public.create_notification(NEW.following_id, 'follow', '👤 New Follower', v_follower_name || ' started following you', jsonb_build_object('follower_id', NEW.follower_id, 'screen', '/notifications'));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_new_follow ON public.follows;
CREATE TRIGGER on_new_follow AFTER INSERT OR UPDATE ON public.follows FOR EACH ROW WHEN (NEW.status = 'active') EXECUTE FUNCTION internal.notify_on_new_follow();

-- ============================================================
-- 3. AI USAGE MONITORING TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION internal.notify_on_ai_usage()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_total_tokens INTEGER;
  v_quota INTEGER;
  v_usage_percent FLOAT;
BEGIN
  SELECT SUM(tokens_used), COALESCE(MAX(token_quota), 10000) INTO v_total_tokens, v_quota
  FROM public.ai_history WHERE user_id = NEW.user_id AND created_at >= DATE_TRUNC('month', CURRENT_TIMESTAMP);

  IF v_quota = 0 THEN RETURN NEW; END IF;
  v_usage_percent := (v_total_tokens::FLOAT / v_quota::FLOAT) * 100;

  IF v_usage_percent >= 100 THEN
    INSERT INTO public.notification_queue (user_id, type, title, body, data)
    VALUES (NEW.user_id, 'ai_token_limit', '🚫 AI Token Limit Reached', 'You have hit your monthly AI quota.', jsonb_build_object('tokens', v_total_tokens, 'quota', v_quota, 'screen', '/settings/ai'));
    PERFORM public.create_notification(NEW.user_id, 'ai_token_limit', '🚫 AI Token Limit Reached', 'You have hit your monthly AI quota.', jsonb_build_object('tokens', v_total_tokens, 'quota', v_quota, 'screen', '/settings/ai'));
  ELSIF v_usage_percent >= 90 THEN
    INSERT INTO public.notification_queue (user_id, type, title, body, data)
    VALUES (NEW.user_id, 'ai_token_warning', '⚠️ AI Tokens Running Low', 'You have used ' || ROUND(v_usage_percent::numeric, 0) || '% of your monthly AI quota.', jsonb_build_object('tokens', v_total_tokens, 'quota', v_quota, 'screen', '/settings/ai'));
    PERFORM public.create_notification(NEW.user_id, 'ai_token_warning', '⚠️ AI Tokens Running Low', 'You have used ' || ROUND(v_usage_percent::numeric, 0) || '% of your monthly AI quota.', jsonb_build_object('tokens', v_total_tokens, 'quota', v_quota, 'screen', '/settings/ai'));
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_ai_usage AFTER INSERT ON public.ai_history FOR EACH ROW EXECUTE FUNCTION internal.notify_on_ai_usage();

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke (Production Hardening)
REVOKE ALL ON TABLE public.notification_queue FROM PUBLIC, anon, authenticated;

-- 2. Limited authenticated access
GRANT SELECT ON TABLE public.notification_queue TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- 4. PG_NET WEBHOOK ERROR MONITORING VIEW
-- ============================================================
-- Crucial visibility helper to debug background HTTP posts failing
-- inside PostgreSQL without hunting down raw engine system tables.
CREATE OR REPLACE VIEW internal.notification_webhook_errors AS
SELECT 
    id AS response_id,
    status_code AS http_status,
    error_msg,
    created AS created_at,
    content AS response_content
FROM net._http_response
WHERE status_code < 200 OR status_code >= 300 OR error_msg IS NOT NULL
ORDER BY created DESC;

-- Grant access to service role for easy API visibility
GRANT SELECT ON internal.notification_webhook_errors TO service_role;


-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.notification_queue table ready';
END $$;
