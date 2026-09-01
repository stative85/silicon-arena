"""
Silicon Arena — Audio Generator
Generates all SFX via ElevenLabs Sound Effects API.
Run: python generate_arena_audio.py
"""

import os
import sys
import time
import requests

API_KEY = os.environ.get("ELEVENLABS_API_KEY", "")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "audio")
ENDPOINT = "https://api.elevenlabs.io/v1/sound-generation"

# Each entry: (filename, prompt, duration_seconds)
SOUNDS = [
    # === AMBIENT ===
    ("arena_drone_low.mp3",
     "Dark ambient electronic drone, low rumbling synthesizer pad, subtle digital hum, "
     "mysterious and ominous atmosphere, slow evolving texture, cyberpunk underground feel",
     8.0),

    ("arena_drone_high.mp3",
     "Intense distorted electronic drone, deep pulsing bass with heartbeat rhythm, "
     "red alert warning atmosphere, glitchy digital interference, rising dread and tension",
     8.0),

    # === AGENT SOUNDS ===
    ("agent_blip.mp3",
     "Short subtle digital UI blip, soft futuristic notification tap, clean and minimal",
     0.5),

    ("agent_influence_up.mp3",
     "Quick ascending digital chime, bright positive confirmation sound, short synth rise, "
     "satisfying level-up ping",
     1.0),

    ("agent_influence_down.mp3",
     "Quick descending digital tone, negative feedback buzz, short deflating synth drop, "
     "subtle failure indicator",
     1.0),

    # === BEEF CINEMATIC ===
    ("beef_tension.mp3",
     "Low ominous rumble building slowly, deep sub-bass vibration with distant thunder, "
     "tension before impact, cinematic standoff atmosphere",
     3.0),

    ("beef_banner.mp3",
     "Dramatic cinematic whoosh sweep, heavy metallic transition sound, bold and aggressive, "
     "like a title card slamming into frame",
     1.5),

    ("beef_clash_impact.mp3",
     "Massive cinematic impact hit, deep powerful bass drop with explosive boom, "
     "metallic crunch and shockwave, devastating collision sound",
     1.5),

    ("beef_overdrive.mp3",
     "Epic cinematic double impact, two massive hits with golden shimmering resonance between them, "
     "legendary tier clash, overwhelming power, echoing metallic boom with bright overtones",
     2.5),

    # === CHAOS EVENTS ===
    ("event_glitch.mp3",
     "Short digital glitch distortion, electronic corruption burst, data breaking apart, "
     "cyberpunk malfunction stutter",
     1.0),

    ("event_cascade.mp3",
     "Deep explosive boom with glass shattering, massive system failure sound, "
     "digital infrastructure collapsing, reverberating destruction",
     2.0),

    ("event_chaos.mp3",
     "Reality warping sound effect, reversed echoes with pitch shifting, "
     "dimensional rift opening, surreal and disorienting audio distortion",
     1.5),

    # === UI ===
    ("screenshot_shutter.mp3",
     "Camera shutter click sound, crisp mechanical snap, clean photo capture, satisfying click",
     0.5),

    ("doom_rising.mp3",
     "Cinematic tension riser, building orchestral swell with electronic elements, "
     "approaching danger, escalating dread, ending abruptly at peak",
     3.0),
]


def main():
    if not API_KEY:
        print("\n  ERROR: ELEVENLABS_API_KEY environment variable not set.")
        print("  Set it with: set ELEVENLABS_API_KEY=your_key_here")
        print("  Get a key at: https://elevenlabs.io/\n")
        sys.exit(1)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"\n  Silicon Arena Audio Generator")
    print(f"  Output: {OUTPUT_DIR}")
    print(f"  Sounds: {len(SOUNDS)}\n")

    # Quick auth check
    r = requests.get("https://api.elevenlabs.io/v1/user/subscription",
                     headers={"xi-api-key": API_KEY})
    if r.status_code != 200:
        print(f"  AUTH FAILED ({r.status_code}): {r.text}")
        sys.exit(1)

    sub = r.json()
    status = sub.get("status", "unknown")
    if status == "past_due":
        print(f"  WARNING: Subscription is past_due — generation may be blocked.")
        print(f"  Fix payment at elevenlabs.io/billing then re-run.\n")

    headers = {
        "xi-api-key": API_KEY,
        "Content-Type": "application/json",
    }

    success = 0
    failed = 0

    for filename, prompt, duration in SOUNDS:
        path = os.path.join(OUTPUT_DIR, filename)

        if os.path.exists(path) and os.path.getsize(path) > 1000:
            print(f"  SKIP (exists): {filename}")
            success += 1
            continue

        print(f"  Generating: {filename} ({duration}s)...", end=" ", flush=True)

        try:
            resp = requests.post(ENDPOINT, headers=headers, json={
                "text": prompt,
                "duration_seconds": duration,
            }, timeout=60)

            if resp.status_code == 200:
                with open(path, "wb") as f:
                    f.write(resp.content)
                size_kb = len(resp.content) / 1024
                print(f"OK ({size_kb:.0f} KB)")
                success += 1
            else:
                print(f"FAILED ({resp.status_code})")
                try:
                    err = resp.json()
                    print(f"         {err.get('detail', {}).get('message', resp.text[:100])}")
                except Exception:
                    print(f"         {resp.text[:100]}")
                failed += 1

        except Exception as e:
            print(f"ERROR: {e}")
            failed += 1

        # Small delay to avoid rate limiting
        time.sleep(1)

    print(f"\n  Done! {success} generated, {failed} failed.")
    print(f"  Files in: {OUTPUT_DIR}\n")


if __name__ == "__main__":
    main()
