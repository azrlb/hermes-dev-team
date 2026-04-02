#!/usr/bin/env node
/**
 * Pi Coding Agent MCP Server — Worker Thread Isolation
 *
 * Fixes the stdin deadlock from S1.1:
 *   - StdioServerTransport owns process.stdin/stdout on the MAIN thread
 *   - Pi SDK session runs in a WORKER thread with its own I/O context
 *   - Main thread <-> worker communicate via postMessage (MessageChannel)
 *
 * Root cause of the original deadlock AND the secondary crash:
 *   1. Pi SDK's session.prompt() hangs when StdioServerTransport owns stdin
 *   2. Pi SDK's output-guard.js redirects process.stdout in the worker,
 *      which shares stdout with the main thread, corrupting MCP protocol
 *      and causing an unhandled error that kills the worker.
 *
 * Solution: In the worker, redirect process.stdout to stderr BEFORE
 * importing Pi SDK, so Pi can write freely without touching MCP's stdout.
 *
 * Architecture:
 *   Main Thread                          Worker Thread
 *   ─────────────                        ─────────────
 *   StdioServerTransport                 Pi SDK Session
 *     ↕ stdin/stdout (MCP protocol)       (stdout → stderr, isolated)
 *     │                                   │
 *     │  postMessage({cmd:'prompt', ...}) ─→  session.prompt(text)
 *     │  ←─ postMessage({result, tokens})    API call → Anthropic
 *     │                                   │
 *   MCP tool handler resolves            Pi execution isolated
 */

import { Worker, isMainThread, parentPort } from 'worker_threads';
import { fileURLToPath } from 'url';

// ============================================================================
// WORKER THREAD — Pi SDK lives here, isolated from MCP's stdin/stdout
// ============================================================================

if (!isMainThread) {
  // CRITICAL: Redirect process.stdout to stderr BEFORE importing Pi SDK.
  // Pi SDK's output-guard.js monkeypatches process.stdout.write to redirect
  // output. If we allow it to write to the real stdout, it will corrupt the
  // MCP JSON-RPC protocol stream on the main thread.
  // Redirecting to stderr is safe — stderr is not used by MCP protocol.
  const originalStdoutWrite = process.stdout.write.bind(process.stdout);
  process.stdout.write = (...args) => process.stderr.write(...args);

  // Intercept process.exit() — Pi SDK or extensions may call it during cleanup,
  // which kills the worker thread. Instead, just log it and let the worker stay alive.
  const originalExit = process.exit;
  process.exit = (code) => {
    process.stderr.write(`[pi-worker] process.exit(${code}) intercepted — worker staying alive\n`);
    // Don't actually exit — the worker thread should only die via terminate() from main thread
  };

  // Also add error handlers so worker crashes are visible
  process.on('uncaughtException', (e) => {
    process.stderr.write('[pi-worker] uncaughtException: ' + e.message + '\n');
    // Don't exit — try to keep the worker alive
  });
  process.on('unhandledRejection', (reason) => {
    process.stderr.write('[pi-worker] unhandledRejection: ' + (reason?.message || String(reason)) + '\n');
  });

  await runWorker();
} else {
  await runMainThread();
}

// ============================================================================
// Worker implementation — Pi SDK in isolated I/O context
// ============================================================================

async function runWorker() {
  const {
    AuthStorage,
    createAgentSession,
    createCodingTools,
    createReadOnlyTools,
    ModelRegistry,
    SessionManager,
    SettingsManager,
    getLastAssistantUsage,
  } = await import('@mariozechner/pi-coding-agent');

  let session = null;
  let authStorage = null;
  let modelRegistry = null;
  let totalTokensIn = 0;
  let totalTokensOut = 0;

  const sessionDir = process.env.PI_SESSION_DIR
    || `${process.env.HOME}/.pi/agent/sessions`;

  function ensureAuth() {
    if (!authStorage) {
      authStorage = AuthStorage.create();
    }
    if (!modelRegistry) {
      modelRegistry = new ModelRegistry(authStorage);
    }
  }

  async function createSession(cwd, mode = 'full', thinkingLevel = 'medium') {
    ensureAuth();

    const allTools = mode === 'readonly'
      ? createReadOnlyTools(cwd)
      : createCodingTools(cwd).filter(t => t.name !== 'bash');

    const settingsManager = SettingsManager.inMemory({
      compaction: { enabled: true },
      retry: { enabled: true, maxRetries: 3 },
    });

    const sessionManager = SessionManager.create(cwd, sessionDir);

    const { session: newSession } = await createAgentSession({
      cwd,
      authStorage,
      modelRegistry,
      tools: allTools,
      thinkingLevel,
      sessionManager,
      settingsManager,
    });

    session = newSession;
    totalTokensIn = 0;
    totalTokensOut = 0;
    return session;
  }

  async function runPrompt(text) {
    if (!session) {
      throw new Error('No active session. Create one first.');
    }

    const textParts = [];
    const toolActions = [];
    let lastUsage = null;

    const unsubscribe = session.subscribe((event) => {
      if (
        event.type === 'message_update' &&
        event.assistantMessageEvent?.type === 'text_delta'
      ) {
        textParts.push(event.assistantMessageEvent.delta);
      }

      if (event.type === 'message_end' && event.message?.role === 'assistant') {
        if (event.message.usage) {
          lastUsage = event.message.usage;
        }
      }

      if (event.type === 'tool_execution_start') {
        toolActions.push({
          tool: event.toolName || 'unknown',
          input: event.input || {},
          status: 'started',
        });
      }
      if (event.type === 'tool_execution_end') {
        const last = [...toolActions].reverse().find(t => t.status === 'started');
        if (last) {
          last.status = 'completed';
          last.result = event.result || '(no output)';
        }
      }
    });

    try {
      await session.prompt(text);
    } finally {
      unsubscribe();
    }

    // Fallback: try to get usage from session entries if event didn't fire
    if (!lastUsage && session.sessionManager) {
      try {
        const entries = session.sessionManager.getEntries();
        lastUsage = getLastAssistantUsage(entries);
      } catch (e) {
        // Ignore — usage is optional metadata
      }
    }

    if (lastUsage) {
      totalTokensIn += lastUsage.input || 0;
      totalTokensOut += lastUsage.output || 0;
    }

    return {
      text: textParts.join('') || '(Pi completed but produced no text output)',
      toolActions,
      usage: lastUsage
        ? {
            tokens_in: lastUsage.input || 0,
            tokens_out: lastUsage.output || 0,
            total_tokens: lastUsage.totalTokens || 0,
          }
        : {
            tokens_in: 0,
            tokens_out: 0,
            total_tokens: 0,
          },
    };
  }

  function getStats() {
    if (!session) {
      return {
        status: 'no active session',
        persistence: 'filesystem',
        sessionDir,
      };
    }

    const state = session.state;
    return {
      status: 'active',
      persistence: 'filesystem',
      sessionDir,
      model: state.model ? `${state.model.provider}/${state.model.id}` : 'unknown',
      thinkingLevel: state.thinkingLevel || 'unknown',
      messageCount: state.messages?.length || 0,
      tools: state.tools?.map(t => t.name) || [],
      cumulativeTokensIn: totalTokensIn,
      cumulativeTokensOut: totalTokensOut,
    };
  }

  async function disposeSession() {
    if (session) {
      try {
        await session.dispose();
      } catch (e) {
        // Ignore dispose errors
      }
      session = null;
      totalTokensIn = 0;
      totalTokensOut = 0;
    }
  }

  // Pre-initialize the session so it's ready when the first prompt arrives
  try {
    const cwd = process.env.PI_CWD || process.env.HOME;
    await createSession(cwd, 'full', 'medium');
    parentPort.postMessage({ type: 'ready' });
  } catch (err) {
    parentPort.postMessage({ type: 'ready_warn', message: err.message });
  }

  // Handle messages from main thread
  parentPort.on('message', async (msg) => {
    const { id, cmd } = msg;

    try {
      if (cmd === 'prompt') {
        const { text, cwd, mode, thinkingLevel } = msg;

        // Create session if needed (e.g., if pre-init failed)
        if (!session) {
          const workDir = cwd || process.env.PI_CWD || process.env.HOME;
          await createSession(workDir, mode || 'full', thinkingLevel || 'medium');
        }

        const result = await runPrompt(text);
        parentPort.postMessage({ id, type: 'result', result });

      } else if (cmd === 'new_session') {
        const { cwd, mode, thinkingLevel } = msg;
        await disposeSession();
        const workDir = cwd || process.env.PI_CWD || process.env.HOME;
        await createSession(workDir, mode || 'full', thinkingLevel || 'medium');
        const stats = getStats();
        parentPort.postMessage({ id, type: 'result', result: stats });

      } else if (cmd === 'status') {
        const stats = getStats();
        parentPort.postMessage({ id, type: 'result', result: stats });

      } else if (cmd === 'dispose') {
        await disposeSession();
        parentPort.postMessage({ id, type: 'result', result: 'disposed' });

      } else {
        parentPort.postMessage({
          id,
          type: 'error',
          error: `Unknown command: ${cmd}`,
        });
      }
    } catch (err) {
      parentPort.postMessage({
        id,
        type: 'error',
        error: err.message || String(err),
      });
    }
  });
}

// ============================================================================
// Main thread implementation — MCP server + worker bridge
// ============================================================================

async function runMainThread() {
  const { McpServer } = await import('@modelcontextprotocol/sdk/server/mcp.js');
  const { StdioServerTransport } = await import('@modelcontextprotocol/sdk/server/stdio.js');
  const { z } = await import('zod');

  // --------------------------------------------------------------------------
  // Spawn the Pi worker thread
  // --------------------------------------------------------------------------

  // The worker runs THIS same file — isMainThread will be false in the worker
  const __filename = fileURLToPath(import.meta.url);

  let worker = null;
  let pendingRequests = new Map(); // id -> { resolve, reject, timer }
  let nextId = 1;
  let workerReadyPromise = null;
  let workerReadyResolve = null;

  workerReadyPromise = new Promise((resolve) => {
    workerReadyResolve = resolve;
  });

  function spawnWorker() {
    worker = new Worker(__filename, {
      env: {
        ...process.env,
      },
    });

    worker.on('message', (msg) => {
      if (msg.type === 'ready' || msg.type === 'ready_warn') {
        if (msg.type === 'ready_warn') {
          process.stderr.write(`[pi-mcp] Worker init warning: ${msg.message}\n`);
        }
        workerReadyResolve();
        return;
      }

      const pending = pendingRequests.get(msg.id);
      if (!pending) return;

      clearTimeout(pending.timer);
      pendingRequests.delete(msg.id);

      if (msg.type === 'error') {
        pending.reject(new Error(msg.error));
      } else {
        pending.resolve(msg.result);
      }
    });

    worker.on('error', (err) => {
      process.stderr.write(`[pi-mcp] Worker error: ${err.message}\n`);
      // Reject all pending requests
      for (const [id, pending] of pendingRequests) {
        clearTimeout(pending.timer);
        pending.reject(new Error(`Worker error: ${err.message}`));
      }
      pendingRequests.clear();
    });

    worker.on('exit', (code) => {
      if (code !== 0) {
        process.stderr.write(`[pi-mcp] Worker exited with code ${code}\n`);
      }
      for (const [id, pending] of pendingRequests) {
        clearTimeout(pending.timer);
        pending.reject(new Error(`Worker exited with code ${code}`));
      }
      pendingRequests.clear();

      // Auto-respawn worker after crash
      // Track rapid crashes (3 within 60s = runaway). Spread-out crashes = normal exit-cleanup bug.
      if (code !== 0) {
        const now = Date.now();
        if (!worker._crashTimes) worker._crashTimes = [];
        worker._crashTimes.push(now);
        // Only count crashes within the last 60 seconds
        worker._crashTimes = worker._crashTimes.filter(t => now - t < 60000);

        if (worker._crashTimes.length <= 3) {
          process.stderr.write(`[pi-mcp] Worker exited — respawning (${worker._crashTimes.length} crashes in last 60s)...\n`);
          workerReadyPromise = new Promise((resolve) => {
            workerReadyResolve = resolve;
          });
          setTimeout(() => spawnWorker(), 2000);
        } else {
          process.stderr.write(`[pi-mcp] Worker crashed 3+ times in 60s — runaway detected. Waiting 30s before retry...\n`);
          worker._crashTimes = []; // Reset after cooldown
          workerReadyPromise = new Promise((resolve) => {
            workerReadyResolve = resolve;
          });
          setTimeout(() => spawnWorker(), 30000); // 30s cooldown then try again
        }
      }
    });
  }

  /**
   * Send a command to the worker and wait for the response.
   * Times out after timeoutMs (default 5 minutes).
   */
  function sendToWorker(cmd, params = {}, timeoutMs = 300000) {
    return new Promise((resolve, reject) => {
      const id = nextId++;
      const timer = setTimeout(() => {
        pendingRequests.delete(id);
        reject(new Error(`Worker command '${cmd}' timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      pendingRequests.set(id, { resolve, reject, timer });
      worker.postMessage({ id, cmd, ...params });
    });
  }

  // Start the worker
  spawnWorker();

  // --------------------------------------------------------------------------
  // MCP Server Setup
  // --------------------------------------------------------------------------

  const server = new McpServer({
    name: 'pi-coding-agent',
    version: '2.1.0',
  });

  /**
   * Tool: pi_prompt
   */
  server.tool(
    'pi_prompt',
    `Send a coding task to the Pi coding agent. Pi is an autonomous coding agent
with full filesystem access (read, write, edit, bash, grep, find, ls). It will
independently analyze code, make changes, run tests, and report results. Use
this for complex coding tasks: refactoring, implementing features, fixing bugs,
writing tests, code review, etc. Pi maintains conversation context across calls
within the same session.`,
    {
      task: z.string().optional().describe(
        'The coding task or question. Be specific about what files, what changes, and what the expected outcome is.'
      ),
      text: z.string().optional().describe(
        'Alias for task — the prompt text to send to Pi.'
      ),
      cwd: z.string().optional().describe(
        'Working directory for Pi. Defaults to $HOME. Set to the project root.'
      ),
      mode: z.enum(['full', 'readonly']).optional().describe(
        'full = read+write+edit+bash (default). readonly = read+grep+find only (safe exploration).'
      ),
      thinking: z.enum(['off', 'minimal', 'low', 'medium', 'high', 'xhigh']).optional().describe(
        "How deeply Pi reasons. 'medium' is a good default. Use 'high' for complex architecture decisions."
      ),
    },
    async ({ task, text, cwd, mode, thinking }) => {
      try {
        const promptText = task || text;
        if (!promptText) {
          return {
            content: [{ type: 'text', text: "Error: provide 'task' or 'text' parameter with the prompt." }],
            isError: true,
          };
        }

        // Wait for worker to be ready (normally immediate after startup)
        await workerReadyPromise;

        const result = await sendToWorker('prompt', {
          text: promptText,
          cwd: cwd || process.env.PI_CWD || process.env.HOME,
          mode: mode || 'full',
          thinkingLevel: thinking || 'medium',
        }, 300000); // 5 minute timeout

        // Format the response
        let response = result.text;

        if (result.toolActions && result.toolActions.length > 0) {
          response += '\n\n--- Actions Taken ---\n';
          for (const action of result.toolActions) {
            const inputSummary = action.tool === 'bash'
              ? (action.input.command || '')
              : (action.input.path || action.input.file || JSON.stringify(action.input).slice(0, 100));
            response += `\n• ${action.tool}: ${inputSummary}`;
            if (action.status === 'completed' && typeof action.result === 'string') {
              const truncated = action.result.length > 500
                ? action.result.slice(0, 500) + '... (truncated)'
                : action.result;
              response += `\n  → ${truncated}`;
            }
          }
        }

        // Append token usage metadata (required by AC3)
        const usage = result.usage;
        response += `\n\n--- Token Usage ---\ntokens_in: ${usage.tokens_in}\ntokens_out: ${usage.tokens_out}\ntotal_tokens: ${usage.total_tokens}`;

        return {
          content: [{ type: 'text', text: response }],
        };
      } catch (error) {
        return {
          content: [{ type: 'text', text: `Pi error: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  /**
   * Tool: pi_status
   */
  server.tool(
    'pi_status',
    "Check Pi's current state: model, thinking level, session size, available tools.",
    {},
    async () => {
      try {
        await workerReadyPromise;
        const stats = await sendToWorker('status', {}, 15000);
        return {
          content: [{ type: 'text', text: JSON.stringify(stats, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: 'text', text: `Error: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  /**
   * Tool: pi_new_session
   */
  server.tool(
    'pi_new_session',
    'Start a fresh Pi coding session. Clears conversation history. Use between unrelated tasks.',
    {
      cwd: z.string().optional().describe('Working directory for the new session'),
      mode: z.enum(['full', 'readonly']).optional().describe('full or readonly'),
      thinking: z.enum(['off', 'minimal', 'low', 'medium', 'high', 'xhigh']).optional().describe(
        'Thinking level for the new session'
      ),
    },
    async ({ cwd, mode, thinking }) => {
      try {
        await workerReadyPromise;
        const stats = await sendToWorker('new_session', {
          cwd: cwd || process.env.PI_CWD || process.env.HOME,
          mode: mode || 'full',
          thinkingLevel: thinking || 'medium',
        }, 60000);

        return {
          content: [{
            type: 'text',
            text: `New Pi session started.\nModel: ${stats.model}\nThinking: ${stats.thinkingLevel}\nTools: ${(stats.tools || []).join(', ')}\nPersistence: ${stats.persistence}`,
          }],
        };
      } catch (error) {
        return {
          content: [{ type: 'text', text: `Error: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  // --------------------------------------------------------------------------
  // Start the MCP server — StdioServerTransport safely on main thread
  // --------------------------------------------------------------------------

  const transport = new StdioServerTransport();
  await server.connect(transport);
  process.stderr.write('[pi-mcp] Pi Coding Agent MCP server v2.1 (worker thread) started\n');

  // Clean shutdown
  const cleanup = async () => {
    try {
      if (worker) {
        await sendToWorker('dispose', {}, 5000).catch(() => {});
        await worker.terminate();
      }
    } catch (e) {
      // Ignore cleanup errors
    }
    process.exit(0);
  };

  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);
}
