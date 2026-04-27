# Lumina Music System Setup Guide

The new music system uses a metadata-driven architecture. This allows you to browse high-quality music data (artwork, bios, lyrics) and play it from your local library.

## 1. Spotify (Metadata & Search)
To enable music search and metadata, you need a Spotify Developer account.
1. Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
2. Create a new App.
3. Name it "Lumina Media" and set the Redirect URI to `http://localhost:8888/callback`.
4. Copy your **Client ID** and **Client Secret**.
5. In Lumina, go to **Settings > Music Providers > Spotify**.
6. Enter your credentials and enable the provider.

## 2. MusicBrainz (Fallback Metadata)
MusicBrainz is enabled by default and used for high-accuracy ID mapping and release group data.
- You can customize the **User Agent** and **Contact Email** in settings to avoid being rate-limited.

## 3. Last.fm (Bios & Tags)
To see artist biographies and genre tags:
1. Get an API key from [Last.fm API](https://www.last.fm/api/account/create).
2. Enter the key in **Settings > Music Providers > Last.fm**.

## 4. ListenBrainz (Recommendations)
ListenBrainz provides personalized music recommendations.
1. Get a User Token from your [ListenBrainz Profile](https://listenbrainz.org/profile/).
2. Enter it in **Settings > Music Providers > ListenBrainz**.

## 5. Local Library Setup
- Add your music folders in **Settings > Audio Sources**.
- The system will automatically index your files and attempt to match them to Spotify/MusicBrainz metadata.
- If a file isn't matched automatically, use the **Review Match Queue** in settings to manually link it.

## 6. Playback
- Use the **Music Library** tab to search for any song, artist, or album.
- Tracks with a green **"LY"** badge are available in your local library and can be played immediately.
- Tracks without the badge are metadata-only. You can manually match them to a local file if you have it.
