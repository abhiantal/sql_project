# ============================================================
# PowerSync Sync Rules
# Single-table SELECTs only. No JOINs, no subqueries.
# Column names match actual schema:
#   comments  → post_id (not target_id, no target_type)
#   reactions → target_id, target_type
# ============================================================

bucket_definitions:

  # ============================================================
  # 👤 ALL USER PROFILES (feed author info + chat participants)
  # ============================================================
  all_profiles:
    data:
      - SELECT * FROM user_profiles

  # ============================================================
  # ⚙️ USER SETTINGS
  # ============================================================
  user_settings:
    parameters:
      - SELECT id FROM user_settings WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM user_settings WHERE id = bucket.id

  # ============================================================
  # 📁 GLOBAL CATEGORIES
  # ============================================================
  global_categories:
    data:
      - SELECT * FROM categories WHERE is_global = true

  # ============================================================
  # 👤 USER CATEGORIES
  # ============================================================
  user_categories:
    parameters:
      - SELECT id FROM categories WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM categories WHERE id = bucket.id

  # ============================================================
  # 🗂️ USER BUCKET MODELS
  # ============================================================
  user_buckets:
    parameters:
      - SELECT id FROM bucket_models WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM bucket_models WHERE id = bucket.id

  # ============================================================
  # 📅 USER DAY TASKS
  # ============================================================
  user_day_tasks:
    parameters:
      - SELECT id FROM day_tasks WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM day_tasks WHERE id = bucket.id

  # ============================================================
  # 📆 USER WEEKLY TASKS
  # ============================================================
  user_weekly_tasks:
    parameters:
      - SELECT id FROM weekly_tasks WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM weekly_tasks WHERE id = bucket.id

  # ============================================================
  # 🎯 USER LONG GOALS
  # ============================================================
  user_long_goals:
    parameters:
      - SELECT id FROM long_goals WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM long_goals WHERE id = bucket.id

  # ============================================================
  # 📔 USER DIARY ENTRIES
  # ============================================================
  user_diary_entries:
    parameters:
      - SELECT id FROM diary_entries WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM diary_entries WHERE id = bucket.id

  # ============================================================
  # 📱 OWN POSTS (Offline-enabled)
  # ============================================================
  user_posts:
    parameters:
      - SELECT id FROM posts WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM posts WHERE id = bucket.id

  # ============================================================
  # 🔖 SAVED POSTS CONTENT (Offline-enabled)
  # ============================================================
  saved_posts_content:
    parameters:
      - SELECT post_id AS id FROM saves WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM posts WHERE id = bucket.id

  # ============================================================
  # 📢 GLOBAL ADVERTISEMENTS
  # All devices sync active ads for offline visibility
  # ============================================================
  global_advertisements:
    data:
      - SELECT * FROM posts
          WHERE is_sponsored = true
          AND ad_status = 'approved'

  # ============================================================
  # ❤️ OWN REACTIONS
  # ============================================================
  user_reactions:
    parameters:
      - SELECT id FROM reactions WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM reactions WHERE id = bucket.id

  # ============================================================
  # ❤️ COMMENTS & REACTIONS ON ACCESSIBLE POSTS
  # Offline-enabled for own posts, saved posts, and own comments
  # ============================================================
  own_posts_comments:
    parameters:
      - SELECT id FROM posts WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM comments WHERE post_id = bucket.id

  own_posts_reactions:
    parameters:
      - SELECT id FROM posts WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM reactions WHERE target_id = bucket.id AND target_type = 'post'

  own_comments_reactions:
    parameters:
      - SELECT id FROM comments WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM reactions WHERE target_id = bucket.id AND target_type = 'comment'

  saved_posts_comments:
    parameters:
      - SELECT post_id AS id FROM saves WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM comments WHERE post_id = bucket.id

  saved_posts_reactions:
    parameters:
      - SELECT post_id AS id FROM saves WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM reactions WHERE target_id = bucket.id AND target_type = 'post'

  # ============================================================
  # 💬 OWN COMMENTS
  # ============================================================
  user_comments:
    parameters:
      - SELECT id FROM comments WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM comments WHERE id = bucket.id

  # ============================================================
  # 💬 REPLIES TO USER (comments where reply_to_user_id = me)
  # ============================================================
  replies_to_user:
    parameters:
      - SELECT id FROM comments WHERE reply_to_user_id = token_parameters.user_id
    data:
      - SELECT * FROM comments WHERE id = bucket.id

  # ============================================================
  # 👥 USER FOLLOWING
  # ============================================================
  user_following:
    parameters:
      - SELECT id FROM follows WHERE follower_id = token_parameters.user_id
    data:
      - SELECT * FROM follows WHERE id = bucket.id

  # ============================================================
  # 👥 USER FOLLOWERS
  # ============================================================
  user_followers:
    parameters:
      - SELECT id FROM follows WHERE following_id = token_parameters.user_id
    data:
      - SELECT * FROM follows WHERE id = bucket.id

  # ============================================================
  # 🔖 USER SAVES
  # ============================================================
  user_saves:
    parameters:
      - SELECT id FROM saves WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM saves WHERE id = bucket.id

  # ============================================================
  # 👁️ USER POST VIEWS
  # ============================================================
  user_post_views:
    parameters:
      - SELECT id FROM post_views WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM post_views WHERE id = bucket.id

  # ============================================================
  # 🔔 USER NOTIFICATIONS
  # ============================================================
  user_notifications:
    parameters:
      - SELECT id FROM notifications WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM notifications WHERE id = bucket.id

  # ============================================================
  # 💬 CHAT: User's own memberships
  # ============================================================
  user_chat_memberships:
    parameters:
      - SELECT id FROM chat_members WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM chat_members WHERE id = bucket.id

  # ============================================================
  # 💬 CHAT: Chats user belongs to
  # ============================================================
  user_chats:
    parameters:
      - SELECT chat_id AS id FROM chat_members
          WHERE user_id = token_parameters.user_id
          AND is_active = true
    data:
      - SELECT * FROM chats WHERE id = bucket.id

  # ============================================================
  # 💬 CHAT: All members of user's chats
  # ============================================================
  chat_all_members:
    parameters:
      - SELECT chat_id AS id FROM chat_members
          WHERE user_id = token_parameters.user_id
          AND is_active = true
    data:
      - SELECT * FROM chat_members WHERE chat_id = bucket.id

  # ============================================================
  # 💬 CHAT: Messages in user's chats
  # ============================================================
  chat_messages:
    parameters:
      - SELECT chat_id AS id FROM chat_members
          WHERE user_id = token_parameters.user_id
          AND is_active = true
    data:
      - SELECT * FROM chat_messages WHERE chat_id = bucket.id

  # ============================================================
  # 💬 CHAT: Attachments in user's chats
  # ============================================================
  chat_attachments:
    parameters:
      - SELECT chat_id AS id FROM chat_members
          WHERE user_id = token_parameters.user_id
          AND is_active = true
    data:
      - SELECT * FROM chat_message_attachments WHERE chat_id = bucket.id

  # ============================================================
  # 💬 CHAT: Invites (owner)
  # ============================================================
  chat_invites_owner:
    parameters:
      - SELECT chat_id AS id FROM chat_members
          WHERE user_id = token_parameters.user_id
          AND is_active = true
          AND role = 'owner'
    data:
      - SELECT * FROM chat_invites WHERE chat_id = bucket.id AND is_active = true

  # ============================================================
  # 💬 CHAT: Invites (admin)
  # ============================================================
  chat_invites_admin:
    parameters:
      - SELECT chat_id AS id FROM chat_members
          WHERE user_id = token_parameters.user_id
          AND is_active = true
          AND role = 'admin'
    data:
      - SELECT * FROM chat_invites WHERE chat_id = bucket.id AND is_active = true

  # ============================================================
  # 📊 PERFORMANCE ANALYTICS
  # ============================================================
  user_performance_analytics:
    parameters:
      - SELECT id FROM performance_analytics WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM performance_analytics WHERE id = bucket.id

  # ============================================================
  # ⚔️ BATTLE CHALLENGES
  # ============================================================
  user_battles:
    parameters:
      - SELECT id FROM battle_challenges WHERE user_id = token_parameters.user_id
    data:
      - SELECT * FROM battle_challenges WHERE id = bucket.id

  # ============================================================
  # 🤝 MENTORSHIP CONNECTIONS (as owner)
  # ============================================================
  user_mentorships_owner:
    parameters:
      - SELECT id FROM mentorship_connections WHERE owner_id = token_parameters.user_id
    data:
      - SELECT * FROM mentorship_connections WHERE id = bucket.id

  # ============================================================
  # 🤝 MENTORSHIP CONNECTIONS (as mentor)
  # ============================================================
  user_mentorships_mentor:
    parameters:
      - SELECT id FROM mentorship_connections WHERE mentor_id = token_parameters.user_id
    data:
      - SELECT * FROM mentorship_connections WHERE id = bucket.id

# ============================================================
# VERIFICATION
# ============================================================
# ✅ PowerSync Sync Rules configuration ready
# No execution needed - this is a YAML configuration file