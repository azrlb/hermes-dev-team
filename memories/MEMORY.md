Also: LivingApp-Platform and LivingApp-Sidecar live at /media/bob/I/AI_Projects/.
§
FlowInCash: financial management platform. TypeScript/React 18/Express/PostgreSQL, Vite frontend, Plaid banking API, Docker+K8s deploy, Prometheus/Grafana monitoring. Path: /media/bob/I/AI_Projects/FlowInCash. Commands: npm run dev, npm test, npm run db:migrate.
§
FliC-MicroApps: 3 ChatGPT MCP micro-apps (budget-builder, goal-tracker, traffic-light). npm workspaces monorepo at /media/bob/I/AI_Projects/FliC-MicroApps. All use @flowincash/mcp-tools via manual symlink. 276 tests total. Deploy: ChatGPT GPT Actions.
§
Crispi-app: meal planning platform in closed beta. React + React Native, Node.js API on AWS Lambda, PostgreSQL, AWS CDK. Path: /media/bob/I/AI_Projects/Crispi-app.
§
Crispi-MicroApps: 5 ChatGPT MCP micro-apps for meal planning. Same MCP pattern as FliC-MicroApps. Path: /media/bob/I/AI_Projects/Crispi-MicroApps.
§
Cross-repo dependency: @flowincash/mcp-tools is the shared MCP foundation. Changes there ripple to ALL 8 MicroApps. npm install silently fails for it — must use manual symlink.
§
All 4 repos use Beads (bd v0.54.0, Dolt backend) for git-backed issue tracking. Session close: git add . && bd sync && git commit && bd sync && git push.
§
FlowInCash and Crispi deploy on Railway; microapps are ChatGPT gateway/marketing entry points. Track alpha/beta status as Bob updates.
§
Brand domain spelling for social/content is FlowInCash (flowincash.com), not FlowInCase.
§
FlowInCash onboarding video workflow lives in /media/bob/I/AI_Projects/FlowInCash/docs/; use the docs folder as the source of truth for script, voiceover, shot list, and captions files (e.g. ONBOARDING-VIDEO-SCRIPT.md). Keep edits in place and avoid duplicate copies.
§
Telegram watchdog: Bob's desktop runs a separate Hermes instance with cron jobs that report via Telegram. This chat session is separate from that instance. Desktop Hermes is the active watchdog; this session is a secondary/on-demand assistant. Working directory for this session: /home/bob.