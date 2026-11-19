# lapswimupdate

## Members-only check

Lap swim signups are checked against the active-membership list, which is kept
privately in Supabase (the page only gets a yes/no back).

To load or refresh the list after exporting a new agreements CSV:

1. `python3 tools/update_members.py path/to/agreements.csv`
2. Open the Supabase SQL editor, paste the generated `members_load.sql`, and run it.

Don't commit the CSV or `members_load.sql`; they contain members' names.
