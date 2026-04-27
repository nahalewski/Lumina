
# Lumina — Feature & Architecture Ideas

## Core Vision

Build a **next-gen personal streaming platform** that feels like:

- Netflix UI
- Plex backend
- AI-powered discovery
- Live TV-style experience from your own library

---

# 1. Core Media System

## TV Show Structure

Show → Season → Episode

Each episode includes:

- show_title  
- season_number  
- episode_number  
- episode_title  
- runtime  
- thumbnail  
- subtitles  
- audio_tracks  
- metadata_id  

Supports parsing:

- S01E01  
- 1x01  
- Season 1 Episode 1  

---

## Movie System

Each movie includes:

- title  
- year  
- poster  
- backdrop  
- synopsis  
- genres  
- actors  
- director  
- rating  
- runtime  
- subtitles  
- audio tracks  

---

## Filters

- Genre  
- Year  
- Rating  
- Actor  
- Director  
- Runtime  
- Resolution  
- Language  
- Watched / Unwatched  

---

# 2. AI Features

## AI TV Guide (Flagship Feature) new side tab

Generate **live TV-style channels** from your library.

### Modes

- Flexible Guide (start from beginning)  
- True Live (real-time playback)  

### Channel Examples

- 90s Throwback  
- Sci-Fi Zone  
- Action Theater  
- Anime After Dark  
- Comedy Couch  
- Horror Late Night  
- Family Room  
- Random Discovery  

---

## AI Program Director

User prompt example:

Build me a Saturday night guide from 6 PM–2 AM with action and comedy.

AI generates full lineup.

---

## AI Recommendation Assistant

User input example:

I want something funny under 2 hours.

AI filters by:

- runtime  
- mood  
- genres  
- watch history  

---

## Mood-Based Browsing

- Cozy  
- Dark  
- Funny  
- Epic  
- Background TV  
- Late Night  
- Rainy Day  

---

## AI Smart Collections

- Comfort Shows  
- Hidden Gems  
- Movies Under 90 Minutes  
- Unfinished Shows  
- Dad’s Picks  
- Anime Night  

---

## AI Library Doctor

Detect:

- Bad filenames  
- Missing metadata  
- Missing subtitles  
- Low quality files  
- Duplicates  

---

## AI Subtitle Features

- Generate subtitles  
- Translate subtitles  
- Sync subtitles  
- Bilingual subtitles  
- Subtitle quality scoring  

---

## AI Episode Recaps

- “Previously On…”  
- 30s / 1min summaries  
- Character recaps  

---

# 3. Playback Features

## Streaming Quality

- Auto  
- Original  
- 1080p  
- 720p  
- 480p  

---

## Transcoding

- FFmpeg  
- Hardware acceleration (Intel Quick Sync / Apple VideoToolbox)  

---

## Skip Features

- Skip Intro  
- Skip Recap  
- Skip Credits  
- Auto-play next episode  

---

## Video Features

- Timeline preview thumbnails  
- Chapter markers  
- Scene detection  
- Quote search  
- Scene search  

---

## Cinema Mode

- Dim UI  
- Play trailers before movie  
- Custom intro  
- Auto subtitles  

---

# 4. TV Guide / Channel System

## Channel Types

### Genre Channels

- Action  
- Sci-Fi  
- Comedy  
- Horror  
- Drama  

### Mood Channels

- Cozy Night  
- Dark & Gritty  
- High Energy  
- Feel Good  

### Time-Based Channels

- Morning Cartoons  
- Prime Time Movies  
- Late Night Horror  

### Person-Based Channels

- Actor-based channels  
- Favorites channels  
- Custom user channels  

---

## Fake Live Channels

- 24/7 Anime Channel  
- Movie Marathon Channel  
- Sitcom Shuffle  
- Random Discovery  

---

# 5. User Features

## Profiles

- Avatar  
- Watch history  
- Favorites  
- Parental controls  
- Subtitle preferences  
- Quality preferences  

---

## Modes

### Dad Mode

- Simple UI  
- Minimal options  

### Kids Mode

- Content filtering  
- Time limits  
- Safe browsing  

---

## Continue Watching

- Resume playback  
- Next episode suggestion  
- Almost finished detection  

---

## Playlists

- Movie night  
- Holiday playlists  
- Anime arcs  
- Custom collections  

---

# 6. Offline & Sharing

## Offline Downloads

- Movies  
- Episodes  
- Seasons  

Options:

- Wi-Fi only  
- Quality selection  
- Delete after watched  

---

## Trip Mode

Prepare for trip → download X hours of content

---

## Guest Sharing

- Temporary links  
- Expiration limits  
- Stream-only mode  

---

# 7. Social / Interaction

## Watch Party

- Sync playback  
- Chat  
- Reactions  

---

## Voice Control

- Play media  
- Search content  
- Control playback  

---

## Phone as Remote

- Control playback  
- Search from phone  
- Send to TV  

---

# 8. Admin & Server Features

## Mission Control Dashboard

- Active streams  
- CPU / RAM  
- Transcoding jobs  
- Network usage  
- Devices  
- Errors  

---

## Logs

- Playback errors  
- Metadata failures  
- Subtitle issues  
- Transcoding failures  

---

## Analytics

- Most watched  
- Trending  
- Device usage  
- Peak times  

---

# 9. AI + Server Architecture

## Recommended Setup

### Intel i7 NUC

- Media server  
- Streaming  
- AI guide  
- Metadata  
- Small AI models  

---

### Mac Mini M4

- Heavy AI tasks  
- Subtitle generation  
- Translation  
- Larger models  

---

## AI Models

### LLMs

- Qwen 3B  
- Phi Mini  
- Llama 3B  
- Gemma 2B  

---

### Whisper

- Base (NUC)  
- Medium/Large (Mac)  

---

## AI Use Cases

- TV guide generation  
- Recommendations  
- Metadata cleanup  
- Mood tagging  
- Subtitle search  
- Recaps  

---

# 10. Performance Rules

## Priority Rule

Direct Play > Transcoding

---

## Limits

- Direct play: 10+  
- Transcodes: 3  
- AI jobs: 1  

---

## Caching

Cache:

- Posters  
- Thumbnails  
- Subtitles  
- Transcodes  
- AI outputs  
- TV guide  

---

## Job Queues

- library_scan  
- metadata  
- subtitles  
- thumbnails  
- transcode  
- ai_tasks  

---

# 11. API Endpoints

GET /api/library/movies  
GET /api/library/tv  
GET /api/tv/{id}/seasons  
GET /api/guide/channels  
GET /api/guide/schedule  
POST /api/guide/generate  
GET /api/server/status  
GET /api/server/analytics  

---

# 12. Database Tables

- movies  
- tv_shows  
- seasons  
- episodes  
- profiles  
- watch_progress  
- favorites  
- downloads  
- channels  
- schedules  
- logs  
- transcode_jobs  

---

# 13. Standout Features

- AI TV Guide (core feature)  
- AI Program Director  
- Anime Mode  
- Smart Discovery Channel  
- Subtitle AI system  
- Mission Control dashboard  

