# Missing direct source: explicit silent mixer start — app 21

Read-only app-container inspection on the M5 iPad showed output routes Playback 1/2/3/4 and mixer inputs Analogue 1/2, Playback 1/2, Off/Off/Off/Off. The prior planner blocked Output 3 because Playback 3 is not a mixer input.

The planner now offers a silent candidate using the existing assigned inputs when the current direct source is unavailable. It never invents a source assignment or changes hardware on selection. Start mixer explicitly warns that the direct feed will be replaced and sound stops until a fader is raised. All eight coefficients start at zero; existing prepare/verify/connect and durable recovery paths are unchanged. Driver 14 is unchanged. Playback 3/4 and Analogue 3/4 assignment editing is still not implemented; this change provides a usable mixer for the currently assigned sources, not equivalent preservation of an unavailable direct feed.

Host tests verify the candidate is silent and the original rows/assignments are unchanged. Signed Debug build passes. No mixer/routing write or listening acceptance was performed. Prepared-state flag is cleared after successful connection, also correcting the earlier stale dialog/failed-send display issue.
