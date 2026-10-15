// Mail Badge Bridge: sums the unread count of every account's Inbox and
// sends it to the native helper, which shows it as a taskbar badge.

const HOST = "mail_badge_bridge";
let port = null;
let lastSent = null;
let timer = null;

function connect() {
  port = messenger.runtime.connectNative(HOST);
  port.onDisconnect.addListener((p) => {
    console.error("mail-badge-bridge: helper disconnected", p.error);
    port = null;
    lastSent = null;
  });
}

function collectInboxes(folders, out) {
  for (const f of folders || []) {
    const isInbox =
      f.type === "inbox" ||
      (Array.isArray(f.specialUse) && f.specialUse.includes("inbox"));
    if (isInbox) out.push(f);
    collectInboxes(f.subFolders, out);
  }
}

// Only one update runs at a time; a request during a run triggers one rerun,
// so an older, slower run can never overwrite a newer count.
let running = false;
let pending = false;

async function update() {
  if (running) {
    pending = true;
    return;
  }
  running = true;
  do {
    pending = false;
    await computeAndSend();
  } while (pending);
  running = false;
}

async function computeAndSend() {
  try {
    const accounts = await messenger.accounts.list(true);
    const inboxes = [];
    for (const a of accounts) collectInboxes(a.folders, inboxes);

    let total = 0;
    for (const f of inboxes) {
      try {
        const info = await messenger.folders.getFolderInfo(f.id ?? f);
        total += info.unreadMessageCount || 0;
      } catch (e) {
        // One unreadable inbox shouldn't block the badge for the others.
        console.error("mail-badge-bridge: skipping folder", f.path, e);
      }
    }

    if (total === lastSent) return;
    if (!port) connect();
    port.postMessage({ count: total });
    lastSent = total;
  } catch (e) {
    console.error("mail-badge-bridge:", e);
  }
}

// Debounce: many folder events can fire at once.
function scheduleUpdate() {
  clearTimeout(timer);
  timer = setTimeout(update, 500);
}

messenger.folders.onFolderInfoChanged.addListener(scheduleUpdate);
messenger.accounts.onCreated?.addListener(scheduleUpdate);
messenger.accounts.onDeleted?.addListener(scheduleUpdate);

// Resend every 5 minutes so the badge comes back after a Plasma restart.
setInterval(() => { lastSent = null; update(); }, 5 * 60 * 1000);

update();
