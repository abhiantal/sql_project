-- ============================================================
-- 📁 FILE 10: GLOBAL CATEGORIES DATA
-- ============================================================

INSERT INTO public.categories (user_id, category_for, category_type, sub_types, description, color, icon, is_global)
VALUES
-- ═══════════════════════════════════════════════════════════
-- 🎯 LONG GOAL CATEGORIES (6)
-- ═══════════════════════════════════════════════════════════
(NULL, 'long_goal', 'Health & Wellness',
ARRAY['Weight Loss','Muscle Building','Mental Health','Quit Addiction','Better Sleep','Stress Management'],
'Long-term health transformation goals', '#43cea2', '💪', TRUE),

(NULL, 'long_goal', 'Career Growth',
ARRAY['Promotion','Career Switch','Start Business','Build Portfolio','Leadership','Side Hustle'],
'Professional advancement and career milestones', '#ff6b6b', '🚀', TRUE),

(NULL, 'long_goal', 'Education',
ARRAY['Degree','Certification','Master Skill','Learn Language','Research','Professional License'],
'Educational achievements and learning mastery', '#4facfe', '🎓', TRUE),

(NULL, 'long_goal', 'Financial Freedom',
ARRAY['Emergency Fund','Debt Free','Buy Home','Retirement','Investment Portfolio','Passive Income'],
'Long-term financial security goals', '#f7971e', '💎', TRUE),

(NULL, 'long_goal', 'Personal Growth',
ARRAY['Confidence','Communication','Emotional Intelligence','Mindfulness','Self-Discipline','Life Balance'],
'Self-improvement and character development', '#a855f7', '🌱', TRUE),

(NULL, 'long_goal', 'Relationships',
ARRAY['Find Partner','Improve Marriage','Better Parent','Strengthen Friendships','Family Bonds','Social Skills'],
'Building meaningful connections', '#ec4899', '❤️', TRUE),

-- ═══════════════════════════════════════════════════════════
-- 🪣 BUCKET LIST CATEGORIES (5)
-- ═══════════════════════════════════════════════════════════
(NULL, 'bucket', 'Travel & Adventure',
ARRAY['Countries','Road Trips','Backpacking','Luxury Travel','Solo Travel','Cultural Immersion'],
'Dream destinations and travel experiences', '#00d2d3', '✈️', TRUE),

(NULL, 'bucket', 'Life Experiences',
ARRAY['Skydiving','Scuba Diving','Marathon','Concert','Festival','Extreme Sports'],
'Once-in-a-lifetime adventures and thrills', '#ff9f43', '🎢', TRUE),

(NULL, 'bucket', 'Creative Dreams',
ARRAY['Write Book','Learn Instrument','Create Art','Start Podcast','Make Film','Design App'],
'Artistic and creative aspirations', '#f368e0', '🎨', TRUE),

(NULL, 'bucket', 'Achievements',
ARRAY['Public Speaking','Publish Work','Win Competition','Get Featured','Build Community','Mentor Others'],
'Recognition and accomplishment goals', '#ffd700', '🏆', TRUE),

(NULL, 'bucket', 'Lifestyle Dreams',
ARRAY['Dream Home','Dream Car','Minimalism','Digital Nomad','Early Retirement','Philanthropy'],
'Ideal lifestyle and living aspirations', '#26de81', '🏡', TRUE),

-- ═══════════════════════════════════════════════════════════
-- 📅 DAILY TASK CATEGORIES (5)
-- ═══════════════════════════════════════════════════════════
(NULL, 'day_task', 'Morning Routine',
ARRAY['Wake Up Early','Meditation','Exercise','Journaling','Healthy Breakfast','Plan Day'],
'Start your day right with morning habits', '#ffeaa7', '🌅', TRUE),

(NULL, 'day_task', 'Work & Focus',
ARRAY['Deep Work','Meetings','Emails','Reports','Collaboration','Learning'],
'Daily work tasks and professional duties', '#74b9ff', '💼', TRUE),

(NULL, 'day_task', 'Daily Health',
ARRAY['Workout','10K Steps','Drink Water','Healthy Meals','Vitamins','Stretch'],
'Daily health and fitness activities', '#55efc4', '🏃', TRUE),

(NULL, 'day_task', 'Evening Routine',
ARRAY['Review Day','Prepare Tomorrow','Family Time','Wind Down','Limit Screens','Sleep Prep'],
'End your day with intentional habits', '#b8b5ff', '🌙', TRUE),

(NULL, 'day_task', 'Self-Care',
ARRAY['Mindfulness','Reading','Gratitude','Hobby Time','Social Connection','Rest'],
'Daily mental wellness and self-care', '#fd79a8', '🧘', TRUE),

-- ═══════════════════════════════════════════════════════════
-- 📆 WEEKLY TASK CATEGORIES (4)
-- ═══════════════════════════════════════════════════════════
(NULL, 'weekly_task', 'Home Management',
ARRAY['Deep Cleaning','Laundry','Grocery Shopping','Meal Prep','Organize','Maintenance'],
'Weekly household chores and home care', '#fad0c4', '🏠', TRUE),

(NULL, 'weekly_task', 'Weekly Review',
ARRAY['Goal Review','Budget Check','Calendar Planning','Progress Assessment','Adjust Plans','Celebrate Wins'],
'Weekly planning and reflection sessions', '#a29bfe', '📊', TRUE),

(NULL, 'weekly_task', 'Social & Family',
ARRAY['Family Dinner','Friend Meetup','Date Night','Call Parents','Community Event','Group Activity'],
'Weekly social connections and quality time', '#ff7675', '👨‍👩‍👧‍👦', TRUE),

(NULL, 'weekly_task', 'Weekly Growth',
ARRAY['Course Progress','Book Reading','Skill Practice','Side Project','Content Creation','Networking'],
'Weekly learning and development activities', '#00cec9', '📈', TRUE);




INSERT INTO public.categories (user_id, category_for, category_type, sub_types, description, color, icon, is_global)
VALUES
-- ═══════════════════════════════════════════════════════════
-- 🌍 COMMUNITY CATEGORIES (8)
-- ═══════════════════════════════════════════════════════════
(NULL, 'community', 'Travel & Adventure',
ARRAY['Backpacking','Road Trips','Cultural Exchange','Solo Travel','Luxury Travel','Digital Nomad'],
'Community travel experiences and adventures', '#FF6B6B', '✈️', TRUE),

(NULL, 'community', 'Food & Cooking',
ARRAY['Recipe Sharing','Meal Prep','Restaurant Reviews','Baking','Vegan Cooking','Wine Tasting'],
'Culinary experiences and food lovers community', '#FFB347', '🍳', TRUE),

(NULL, 'community', 'Arts & Creativity',
ARRAY['Painting','Photography','Writing','Music','DIY Crafts','Digital Art'],
'Creative expression and artistic collaboration', '#9B59B6', '🎨', TRUE),

(NULL, 'community', 'Sports & Recreation',
ARRAY['Running','Cycling','Yoga','Team Sports','Hiking','Swimming'],
'Active lifestyle and recreational activities', '#3498DB', '⚽', TRUE),

(NULL, 'community', 'Learning & Education',
ARRAY['Book Club','Language Learning','Online Courses','Workshops','Mentorship','Study Groups'],
'Community learning and skill development', '#2ECC71', '📚', TRUE),

(NULL, 'community', 'Technology & Innovation',
ARRAY['Coding','AI & ML','Blockchain','Gadgets','Startups','Tech News'],
'Tech enthusiasts and innovation community', '#34495E', '💻', TRUE),

(NULL, 'community', 'Parenting & Family',
ARRAY['New Parents','Toddler Activities','School Age','Teenagers','Family Events','Parenting Tips'],
'Family life and parenting support community', '#E84342', '👨‍👩‍👧', TRUE),

(NULL, 'community', 'Sustainability & Environment',
ARRAY['Zero Waste','Gardening','Recycling','Green Energy','Conservation','Eco Products'],
'Eco-conscious living and environmental action', '#27AE60', '🌱', TRUE),

-- ═══════════════════════════════════════════════════════════
-- 🏠 LOCAL COMMUNITY CATEGORIES (4)
-- ═══════════════════════════════════════════════════════════
(NULL, 'community', 'Local Events',
ARRAY['Concerts','Festivals','Markets','Meetups','Workshops','Networking'],
'Local community events and gatherings', '#F39C12', '📅', TRUE),

(NULL, 'community', 'Neighborhood Watch',
ARRAY['Safety Alerts','Lost & Found','Community Patrol','Emergency Prep','Crime Prevention','Security Tips'],
'Community safety and neighborhood support', '#C0392B', '🚓', TRUE),

(NULL, 'community', 'Volunteering',
ARRAY['Charity Work','Mentoring','Fundraising','Animal Rescue','Elder Care','Community Cleanup'],
'Giving back to the community through volunteering', '#16A085', '🤝', TRUE),

(NULL, 'community', 'Local Business',
ARRAY['Shop Local','Small Business','Services','Recommendations','Reviews','Deals'],
'Supporting and discovering local businesses', '#2980B9', '🏪', TRUE),

-- ═══════════════════════════════════════════════════════════
-- 💬 SOCIAL COMMUNITY CATEGORIES (4)
-- ═══════════════════════════════════════════════════════════
(NULL, 'community', 'Hobbies & Interests',
ARRAY['Gaming','Gardening','Pets','Collecting','Board Games','Photography'],
'Connect with people who share your hobbies', '#8E44AD', '🎮', TRUE),

(NULL, 'community', 'Support Groups',
ARRAY['Mental Health','Grief Support','Addiction Recovery','Chronic Illness','Caregivers','Anxiety Support'],
'Peer support and safe space communities', '#E67E22', '💚', TRUE),

(NULL, 'community', 'Dating & Relationships',
ARRAY['Dating Tips','Relationship Advice','Friendship','Marriage','Breakups','Dating Safety'],
'Navigating relationships and dating community', '#E91E63', '💑', TRUE),

(NULL, 'community', 'Spirituality & Faith',
ARRAY['Meditation','Prayer Groups','Religious Studies','Mindfulness','Retreats','Spiritual Growth'],
'Spiritual and faith-based community connections', '#9B59B6', '🕊️', TRUE);





INSERT INTO public.categories (user_id, category_for, category_type, sub_types, description, color, icon, is_global, sort_order)
VALUES
-- ═══════════════════════════════════════════════════════════
-- 👥 GROUP CATEGORIES (12)
-- ═══════════════════════════════════════════════════════════

-- Interest-based Groups
(NULL, 'group', 'Hobby & Interests',
ARRAY['Book Club','Gaming','Photography','Cooking','Gardening','Art & Crafts','Music','Film'],
'Groups centered around shared hobbies and interests', '#FF6B6B', '🎨', TRUE, 10),

(NULL, 'group', 'Sports & Fitness',
ARRAY['Football','Basketball','Running','Cycling','Yoga','Gym','Hiking','Swimming'],
'Sports teams and fitness groups', '#4ECDC4', '⚽', TRUE, 20),

(NULL, 'group', 'Professional Networking',
ARRAY['Tech','Marketing','Design','Finance','Startups','Remote Work','Freelancers','Career Growth'],
'Professional networking and career development groups', '#45B7D1', '💼', TRUE, 30),

(NULL, 'group', 'Education & Learning',
ARRAY['Language Exchange','Study Group','Coding','Mathematics','Science','History','Online Courses'],
'Educational and learning-focused groups', '#96CEB4', '📚', TRUE, 40),

-- Location-based Groups
(NULL, 'group', 'Local Community',
ARRAY['Neighborhood','City Events','Local News','Community Service','Local Business','Meetups'],
'Local community groups and neighborhood connections', '#FFEEAD', '🏘️', TRUE, 50),

(NULL, 'group', 'Expat & International',
ARRAY['Expats in City','International Students','Cultural Exchange','Moving Abroad','Multi-cultural'],
'Groups for expats and international communities', '#D4A5A5', '🌏', TRUE, 60),

-- Lifestyle Groups
(NULL, 'group', 'Family & Parenting',
ARRAY['New Parents','Toddlers','School Age','Teenagers','Family Activities','Parenting Tips'],
'Family-oriented and parenting support groups', '#FF9AA2', '👨‍👩‍👧', TRUE, 70),

(NULL, 'group', 'Health & Wellness',
ARRAY['Mental Health','Meditation','Nutrition','Recovery Support','Wellness Tips','Self Care'],
'Health and wellness support groups', '#B5EAD7', '🧘', TRUE, 80),

(NULL, 'group', 'Food & Dining',
ARRAY['Foodies','Restaurant Reviews','Cooking Club','Recipe Sharing','Vegan','Local Eats'],
'Food enthusiasts and dining groups', '#FFB347', '🍜', TRUE, 90),

-- Special Interest Groups
(NULL, 'group', 'Technology & Gaming',
ARRAY['PC Gaming','Console Gaming','Game Dev','Tech News','Gadgets','VR/AR','Esports'],
'Technology enthusiasts and gaming communities', '#A05195', '🎮', TRUE, 100),

(NULL, 'group', 'Arts & Creativity',
ARRAY['Writing','Painting','Digital Art','Photography','DIY','Crafts','Design'],
'Creative and artistic groups', '#F2856D', '🎭', TRUE, 110),

(NULL, 'group', 'Career & Business',
ARRAY['Entrepreneurs','Small Business','Startup Founders','Investors','Mentorship','Industry Experts'],
'Business and career-oriented groups', '#665191', '📈', TRUE, 120);


 
 - -   = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = 
 - -   V E R I F I C A T I O N 
 - -   = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = 
 D O   $ $ 
 B E G I N 
         R A I S E   N O T I C E   ' '  G l o b a l   C a t e g o r i e s   D a t a   R e a d y ' ; 
 E N D   $ $ ;  
 