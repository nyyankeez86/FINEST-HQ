# FINEST HQ — beta section numbers

Shown only to beta testers (approved accounts with `profiles.beta = true`; the admin, zee, is on). Everyone else never sees them.
Each page has a number; each section on it a letter (e.g. **1a**). The tag sits in the section's top corner; the page number sits
by the page's Suggest bar (tabs) or sheet header (sheets). Tapping **Suggest** inside a section pre-fills the Section field with
the tag (e.g. `2d · Paid Detail`); the page-level Suggest pre-fills the page number (e.g. `2 · Overtime`).
IDs are hardcoded in `index.html` (`data-sec="…"`, `TAB_PAGES`, `SHEET_PAGES`). They are never computed from layout order,
so they stay stable when sections move. New sections get the next free letter; retired letters are not reused.

## Tabs (pages 1–5, in tab order)

| Page | Section | What |
|---|---|---|
| **1 Schedule** | 1a | Today (compact card in the home strip: status line, plus the actual scheduled tour times only on a working day). Off days (and any other non-working day) do not show the default tour start or length. Reminders each appear on their own line: RDO overtime (an extra tour on an RDO); an assignment (the day assignment or an additional assignment-only entry — e.g. “Court 10:30”); or a paid detail as “Paid Detail:” plus a one-line summary (vendor, time, and a short address if it fits, truncated with an ellipsis). If today is clean, the next upcoming reminder within 7 days may appear as “Tomorrow: …” or “Fri: …”. If there is nothing to show, the card stays clean with no filler line. The card is tappable (chevron) and expands in place with a detailed layout of the day’s tour, each assignment (court location, times, notes), and the paid detail (ID, vendor, times, address lines, amount, paid status). Tapping again collapses it. |
| | 1b | At a Glance (compact two-line card in the home strip, combined with 1c). Next RDO is the start of the next RDO block that is not already in progress. The card is tappable (chevron) and expands in place: the full next RDO block (start–end and number of days) plus the following block. Tapping again collapses it. |
| | 1c | Next Payday (the second line of the At a Glance card). The compact line stays “Next Payday: <date> (Today/Tomorrow/in N days)”. When the card is expanded, it also shows the pay period that payday covers, expected overtime being paid that payday when computable (H:MM), and the next payday after it. |
| | 1d | Calendar (month grid, legend, chart changes; 12 hour tour RDO colors Squad A blue / Squad B red). Scheduled days off are labeled RDO (not “Off”/“OFF”), including Other Calendars overviews (e.g. “A RDO”, “S2 RDO”) and the legend (“Squad A RDO”). There is no monthly days-off counter. OT marks use H:MM (e.g. OT 14:30), not decimal hours. Tour changes (a different start, end, or length on a regular workday; not RDO OT) are not marked on the calendar; a muted “Tour changes: N this month · N this year” line sits under the month grid on My schedule. Dropped workdays still use the gray NOT WKG cell style. Other Calendars is a temporary view of any other chart or overview (patrol squads, 12 hour tour RDO A/B, steady RDO, PDU, or an all-squads overview) without changing the user’s settings, entries, or OT. A banner such as “Viewing: 12 hour tour RDO — Squad B” and a one-tap “Back to my calendar” button appear while peeking. The view is not saved to the profile or sync and resets on reload or Back. |
| | 1e | Upcoming assignments |
| | 1f | Retirement countdown |
| | 1g | Sync to Apple / Google Calendar button |
| | 1h | "Finish your profile" prompt (when shown) |
| **2 Overtime/Paid Detail** | 2a | Totals row (OT period / Month / Year), shown in the Overtime view. The “paid” Friday in this row is the expected pay date. |
| | 2b | + Log overtime |
| | 2c | Overtime entries grouped by year (top level, newest first) then month; groups are collapsible. Compact rows show type, times, hours, expected pay date, and a Paid / Unpaid badge. In Select mode, a selected entry gets a light accent fill and a 2px inset accent border with rounded corners (no layout shift). Swipe right to mark paid (green while dragging, with a matching green border). Swipe left to delete (red while dragging, with a matching red border). Swipes are off in Select mode. |
| | 2d | Paid Detail view: entries grouped the same way (year then month), plus the year-end tax report button. Select mode (same accent fill and 2px inset border as 2c). Swipe right to mark paid (green while dragging; Paid date and Check date dialog; tax year still follows the check date; green border while dragging). Swipe left to delete (red while dragging; confirm; red border while dragging). Swipes are off in Select mode. |
| | 2e | Overtime \| Paid Detail toggle, directly above 2a. |
| | 2f | Select mode, Unpaid / Paid filter, and Mark paid / Mark unpaid. Mark paid opens the mini calendar; the chosen date is stored on each selected OT record as the actual paid date (separate from the expected pay date). |
| **3 Pay** | 3a | Year summary card (includes chart time accrued this year) |
| | 3b | Each payday / pay-period card (straight time is 8:00/day; chart time for the regular period, or pending for rotating Sergeants) |
| **4 Leave** | 4a | Year summary card |
| | 4b | Add leave / note / assignment buttons |
| | 4c | Assignments this year |
| | 4d | Leave & notes list |
| **5 Lookup** | 5a | Date picker card |
| | 5b | Big working / off answer |
| | 5c | "You" line |
| | 5d | Week strip |
| | 5e | PDU lookup (PDU only) |

## Sheets (fixed numbers 6–20)

| Page | Section | What |
|---|---|---|
| **6 Day page** | 6a | Status line (your schedule for that day only by default) |
| | 6b | This day (leave / status picker). Changing a scheduled workday’s status to RDO immediately opens a dialog asking whether the day is Day-for-Day or RDO Overtime, then routes to the matching existing recording flow. Cancel reverts 6b to its previous status. The prompt is not shown when the day was already an RDO, or for other status changes. |
| | 6c | Tour this day: Time actually worked only (framed Date from / Date to, Scheduled time button, empty-until-entered hint on focus). Typing Tour start live-fills Tour end from the default tour length (end date moves if it crosses midnight). A manual Tour end is kept until start is edited again. Time scheduled to work is not on this screen — it appears on page 8 when overtime is incurred. Chart time for the day is shown under the tour when it accrues or is pending. |
| | 6d | Assignment (court picker includes NYC Family Court in each borough; sign-in location field reserved, not shown) |
| | 6e | Paid detail (own section below Assignment: Add paid detail opens page 19; a saved detail shows a summary + Edit). Not an assignment option. |
| | 6f | Note |
| | 6g | Overtime this day |
| | 6h | Delete this entry |
| | 6i | Add to calendar (one-off Google link or Apple .ics; subscribe is recommended) |
| | 6j | Other squads (button on the day page; expands Off / Working / PDU details for other squads; on the 12 hour tour RDO chart, Squad A and Squad B) |
| | 6k | Additional assignment-only entry (from 7e Add another entry, only when a tour is already saved). Types Court, Training, Detail, Other; existing court picker (including family courts) and assignment fields; optional scheduled start and optional end using the app’s 24-hour time-typing rule in framed boxes. Stored as a linked additional entry on tours[iso].entries with kind “assignment”. Does not create a tour or change hours, overtime, chart time, or the tour-change count. Several may be saved on the same day. Shown on the day sheet and 7e in time order, in the calendar assignment badge, in 1a, and in the calendar feed/export as their own timed events (all-day if there is no time). Edit and delete work like other entries. |
| **7 Day summary** | 7a | Entries list. Swipe left to delete the tour entry, an additional (overtime) tour entry, or an assignment-only entry. Same rules as 2c: the row turns red only while dragging, a 72px threshold, a horizontal lock only after |dx|>12 and |dx|>|dy|×1.15 so vertical scroll is not hijacked, the same inset red border, and a confirmation dialog. Cancel snaps the row back. Confirm uses that entry’s existing delete path (linked overtime is removed; assignment-only deletes leave the tour and hours unchanged). There is no swipe-right action in 7a. |
| | 7b | Overtime list |
| | 7c | Edit / Done buttons |
| | 7d | Delete this entry |
| | 7e | Add another entry (opens a choice when a tour is already saved: another overtime tour, or an assignment without a tour time). If no tour is entered yet, the button still opens the additional overtime-tour form, unchanged. Additional assignment-only entries appear in the 7e list in time order with their scheduled time. |
| **8 Overtime entry** | 8a | Date |
| | 8b | Type |
| | 8c | Overtime location (command / precinct) |
| | 8d | Time actually worked (framed Date from / Date to, times, computed Hrs:Min, Default Tour). Always on the overtime slip — not nested under 8k. Typing Time from live-fills Time to from the default tour length. Optional “Total hours only” is a compact entry mode, not this section. |
| | 8e | Paid as (Cash / Time / Split) |
| | 8f | Travel time |
| | 8g | Pay estimate card. The “starts 20:00 or later” note is small and only shown when the entered tour start is 20:00 or later. |
| | 8h | Notes |
| | 8i | Time scheduled to work (same layout + Default Tour). Only on the overtime page, and only when overtime was incurred. Hidden on a scheduled RDO. Never shown on the day screen (6c). |
| | 8j | Total overtime performed (read-only, auto-calculated) |
| | 8k | Compensation option (Cash and Time rows; only when Paid as is Split). Hrs:Min uses the same time-typing rule as the rest of the app. |
| **9 Settings** | 9a | Account |
| | 9b | Profile (first name, M.I. (optional, no asterisk), last name, ID numbers; name boxes aligned on one row) |
| | 9c | Rank & assignment history (chart picker includes 12 hour tour RDO with Squad A / Squad B) |
| | 9d | Pay |
| | 9e | Leave balances |
| | 9f | Google Maps API key (collapsed by default; title button expands it) |
| | 9g | Backup |
| | 9h | Extra 15 minutes (PDU) (shown only when the current command is a PDU / precinct detective squad) |
| | 9i | Schedule rules (hidden; text/engine data kept, not shown) |
| | 9j | Calendar sync (one-time file export; collapsed by default; title button expands it) |
| | 9k | Erase all data |
| | 9l | Default calendar (Google or Apple, for one-off Add to calendar) |
| | 9m | Subscribe to calendar (private feed URL) |
| | 9n | Privacy & Security (never sell data; entries visible only to the account holder; device-only private fields; Delete my account and cloud data) |
| **10 History editor** | 10a | What changes (preview) |
| | 10b | Effective date |
| | 10c | Rank |
| | 10d | Command |
| | 10e | Chart (12 hour tour RDO shows a boxed Squad A / Squad B segmented choice) |
| | 10f | Tour |
| | 10g | Date promoted to rank (optional). Used to measure time in rank for chart time when the effective date is a transfer, not the promotion. |
| | 10h | Investigative assignment (Yes/No), shown for detective ranks. Investigative detectives do not accrue chart time. |
| **11 Send a suggestion** | 11a | Section |
| | 11b | Your suggestion |
| | 11c | Screenshot |
| **12 Suggestions inbox (admin)** | — | header tag only |
| **13 Beta users (admin)** | 13a | User list (approve / revoke / Beta tags on-off) |
| **14 Add leave / note / assignment** | 14a | Date |
| **15 Calendar sync** | 15a | Sync options |
| **16 Extra 15 minutes (PDU)** | — | header tag only |
| **17 Extra 15 month editor** | — | header tag only |
| **18 Chart editor** | — | header tag only |
| **19 Paid detail** | 19a | Paid Detail ID |
| | 19b | Date from / Date to (framed tappable MM/DD/YYYY + date wheel; overnight times move Date to to the next day) |
| | 19c | Start time, End time, and computed Hrs:Min (platform-wide auto-colon typing; the official slip Time range) |
| | 19d | Vendor, with Previous vendors (deduped name+address from past paid details, most recent first, searchable when there are many; picking one fills vendor + both address lines) |
| | 19e | Address Line 1 (street; same address autocomplete as court/training) |
| | 19f | Address Line 2 (city, state, ZIP; trailing “Boro: Q” is stripped) |
| | 19g | Payment: Paid button (mark as paid), optional Paid date (date payment was received), and Check date. Tapping either date opens a mini calendar grid (not the date wheel). Caption under Check date: “This is the date printed on the check, not the day you received it.” Stored in the synced paid-detail record. |
| | 19h | Timing captions at the bottom of a completed detail (only when computable): days from the detail date to the check date (“Vendor issued check N days after the detail”) and from the check date to the paid date (“Received N days after the check date”). |
| | 19i | Amount (optional check amount, $). If blank, pay is hours × the existing flat rank rate already used for paid details. The year-end report uses the entered check amount when present, otherwise the calculated pay. |
| **20 Year-end tax report** | 20a | Tax year picker. Earnings count in the year of the check date (not the work date). If the check date is missing, the paid date is used; details with neither are listed as pending and excluded from that year’s totals. Opened from the Paid Details card (2d). |
| | 20b | Vendor consolidation: suggested groups of likely-same vendors (name similarity / prefix matches such as UBS, Mount Sinai, MSG, Boston Properties, Vornado, NYU, Tishman Speyer), confirm or keep separate, manual combine, rename a group, and remove a vendor that was grouped by mistake. Mapping is stored in synced settings. The report uses the combined name, with locations listed under each. |
| | 20c | Report preview: per-vendor totals (gross by check date), count of details, hours, and a detailed line list (date worked, ID, vendor, location/address, hours, amount, check date, paid date), plus pending / unpaid. |
| | 20d | Export: real .xlsx (Summary + Details sheets, built on the device) and CSV fallback; Email to myself via the device share sheet (navigator.share with the file), falling back to download + mailto. Nothing is uploaded. |
