# PowerSync & Local-First Storage: Table-by-Table Reference Manual

This document details exactly how each database table in your system is stored locally (offline SQLite database via PowerSync sync rules) and how that data is fetched and rendered on the user's screens.

---

## 1. The Core Architectural Philosophy

### A. The Hybrid Data Model (Scales to 1M+ Users)
- **Private/Productivity Data** (Tasks, Goals, Diary, Settings): Stored **100% locally** for the authenticated user. This works instantly, works offline, and syncs seamlessly.
- **Social Content (Posts, Comments, Reactions)**: Uses a hybrid approach to save bandwidth and device storage:
  - **Saved and Authored Content**: Stored locally in SQLite (so the user can always see their own posts and bookmarked items offline).
  - **Shared Social Feed (Other people's posts)**: Queried **online live from Supabase** when online (utilizing server-side Row Level Security for privacy filtering). This keeps device storage small, avoids syncing millions of rows, and scales seamlessly to a million users!

---

## 2. Table-by-Table Storage & Screen Reference

---

### Table 1: `user_profiles`
*   **How it is Stored Locally**: **All profiles** are synced to the local database. Since profile data (usernames, display names, profile avatars) is tiny but queried constantly everywhere (feeds, comments, chat list, follow lists), caching them locally prevents slow server round-trips.
*   **How it is Shown on the Screen**:
    - **User Profile Screen**: Renders bio, posts count, follower count, and display picture.
    - **Feed Posts & Comments**: Placed beside every post card and comment bubble to show the author's identity.
    - **Chat Inbox & Active Chat Sheets**: Shows participant names and profile pictures.

---

### Table 2: `user_settings`
*   **How it is Stored Locally**: Privately partitioned. Only the authenticated user's settings are synchronized and stored in their local SQLite.
*   **How it is Shown on the Screen**:
    - **Settings Screen**: Populates theme toggles (dark mode, light mode), synchronization schedules, notification triggers, and user profile management controls.

---

### Table 3: `categories`
*   **How it is Stored Locally**: Syncs two datasets: (1) All **global categories** (created by admins), and (2) **user-created categories** (created by the logged-in user).
*   **How it is Shown on the Screen**:
    - **Task Creation & Habits sheets**: Populates category dropdown lists (e.g., "Health", "Work", "Finances") used to classify diaries, goals, and tasks.
    - **Stats & Analytical Screens**: Groups time distribution and habit consistency charts by category.

---

### Table 4: `bucket_models`
*   **How it is Stored Locally**: Partitioned privately. Only bucket models created by the logged-in user are stored offline in local SQLite.
*   **How it is Shown on the Screen**:
    - **Time Chart / Bucket Dashboard**: Renders the user's personal buckets as high-premium visual cards, showing tracking categories and time allocation ratios.

---

### Table 5: `day_tasks`
*   **How it is Stored Locally**: Partitioned privately. Contains nested JSON parameters (`about_task`, `timeline`, `indicators`, `metadata`, `feedback`) stored as local text and queried using SQLite's `json_extract()` function.
*   **How it is Shown on the Screen**:
    - **Daily Calendar Screen**: Lists tasks scheduled for the active calendar date.
    - **Home Board Sidebar**: Lists today's high-priority task checklists.
    - **Task Progress Dashboard**: Renders task completion ratios and milestone points.

---

### Table 6: `weekly_tasks`
*   **How it is Stored Locally**: Partitioned privately. Only the authenticated user's weekly tasks are stored offline in their SQLite.
*   **How it is Shown on the Screen**:
    - **Weekly Planning Screen**: Displays weekly goals, milestones, and daily checklist summaries.
    - **Sidebar Panel**: Quick list of active weekly priorities.

---

### Table 7: `long_goals`
*   **How it is Stored Locally**: Partitioned privately. Only goals/habits created by the logged-in user are stored locally.
*   **How it is Shown on the Screen**:
    - **Goals Hub**: Renders active long-term habits, target milestones, and motivational progress bars.
    - **Streak Tracker Grid**: Renders habit streak grids showing continuous daily completions.

---

### Table 8: `diary_entries`
*   **How it is Stored Locally**: Partitioned privately. Only the user's personal journals are stored on their device.
*   **How it is Shown on the Screen**:
    - **Diary Timeline**: Displays entries chronologically with attached images and mood indicators.
    - **Mood Calendar Screen**: Generates a mood color grid mapped over the calendar days.

---

### Table 9: `posts`
*   **How it is Stored Locally**: **Hybrid Scope**:
    1. **User's Own Posts**: Synced automatically to local SQLite so the author can view and edit their portfolio offline.
    2. **Saved Posts**: Synced automatically when bookmarked.
    3. **Other Users' Feed Posts**: **Never stored locally**. They are fetched live online from Supabase Postgres when opening the feed screens, complying with visibility flags (`public`, `followers`, `following`, `private`).
*   **How it is Shown on the Screen**:
    - **Home Social Feed & Explore Grid**: Renders live online posts with media reels, polls, and articles.
    - **Saved/Bookmarked Screen**: Displays saved posts offline.
    - **Self Profile Screen**: Renders authored posts offline.

---

### Table 10: `comments`
*   **How it is Stored Locally**: **Hybrid Scope**:
    1. **Comments on Own Posts**: Synced to SQLite so you can read feed feedback offline.
    2. **Comments on Saved Posts**: Synced to SQLite.
    3. **Other Comments**: Loaded online-only from Supabase when opening a post thread.
*   **How it is Shown on the Screen**:
    - **Comments Bottom Sheet**: Displays threaded comment listings, user mentions, and reply trees.

---

### Table 11: `reactions`
*   **How it is Stored Locally**: **Hybrid Scope**:
    1. **Reactions on Own Posts/Comments**: Synced to local SQLite.
    2. **Reactions on Saved Posts**: Synced to local SQLite.
    3. **Other Reactions**: Loaded dynamically from the online backend.
*   **How it is Shown on the Screen**:
    - **Feed Post Footer**: Shows the tally of reactions (likes, thumbs up, flames, etc.) and lights up the react button if the current user has reacted.

---

### Table 12: `follows`
*   **How it is Stored Locally**: Syncs any relationships where the logged-in user is either the **follower** or the **followed user**.
*   **How it is Shown on the Screen**:
    - **Follower/Following lists**: Rendered on the User Profile screen.
    - **Follow Button**: Renders as "Follow", "Unfollow", "Requested", or "Edit Profile" on profile screens.

---

### Table 13: `saves`
*   **How it is Stored Locally**: Partitioned privately. Stores only the bookmark/saves registry of the current logged-in user.
*   **How it is Shown on the Screen**:
    - **Bookmarks Screen**: Lists all posts saved by the user.
    - **Save Button**: Highlights the bookmark icon on posts to show active save state.

---

### Table 14: `chats`
*   **How it is Stored Locally**: Relational Sync. Syncs **only** chats where the current user is listed as an active member in `chat_members`.
*   **How it is Shown on the Screen**:
    - **Chat Inbox Screen**: Displays lists of group chats, active direct messages, last message previews, and unread badges.

---

### Table 15: `chat_members`
*   **How it is Stored Locally**: Relational Sync. Syncs participants belonging to any of the user's active chats.
*   **How it is Shown on the Screen**:
    - **Group Details Screen**: Renders member rosters, listing administration roles (owner, admin, member).

---

### Table 16: `chat_messages`
*   **How it is Stored Locally**: Relational Sync. Syncs messages belonging to the user's active chats.
*   **How it is Shown on the Screen**:
    - **Active Chat Detail Screen**: Renders interactive chat message bubbles chronologically.

---

### Table 17: `chat_message_attachments`
*   **How it is Stored Locally**: Relational Sync. Syncs media attachment records belonging to the user's active chats.
*   **How it is Shown on the Screen**:
    - **Chat Bubbles & Gallery Grid**: Renders photo thumbnails, video preview players, and file download cards.

---

### Table 18: `chat_invites`
*   **How it is Stored Locally**: Syncs invites for active chats where the current user holds administrative privileges (owner or admin).
*   **How it is Shown on the Screen**:
    - **Group Invite Dashboard**: Displays active invite links, pending requests, and authorization controls.

---

### Table 19: `notifications`
*   **How it is Stored Locally**: Partitioned privately. Only notifications targeted to the logged-in user are stored.
*   **How it is Shown on the Screen**:
    - **Notifications Tray**: Lists activity alerts (likes, comments, new followers, chat invitations).

---

### Table 20: `performance_analytics`
*   **How it is Stored Locally**: Partitioned privately. Stores only the user's analytical records.
*   **How it is Shown on the Screen**:
    - **Analytics Dashboard**: Populates progress charts, productivity scores, task efficiency ratios, and time-tracking insights.
