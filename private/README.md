# private/

This folder never reaches git. It is excluded by `.gitignore` Layer 3.

What belongs here: raw client materials under NDA, exports containing
personal data, `.env` files and credentials, and anything else you need on
this machine but must never sync to the shared repo.

If an operator leaves, their local clone only ever held what this repo
shared with everyone; `private/` was never part of that. It stays theirs,
and there is nothing here to hand off or recover.
