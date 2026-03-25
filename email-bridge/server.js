const express = require('express');
const { ImapFlow } = require('imapflow');
const nodemailer = require('nodemailer');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3100;

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'email-bridge' });
});

// Read emails via IMAP
app.post('/read-emails', async (req, res) => {
  const {
    host, port = 993, user, password,
    folder = 'INBOX', limit = 10, since,
    before, unseen, from
  } = req.body;

  if (!host || !user || !password) {
    return res.status(400).json({ error: 'Missing required fields: host, user, password' });
  }

  const client = new ImapFlow({
    host,
    port: Number(port),
    secure: Number(port) === 993,
    auth: { user, pass: password },
    logger: false
  });

  try {
    await client.connect();
    const lock = await client.getMailboxLock(folder);

    try {
      const searchCriteria = {};
      if (since) {
        // IMAP SINCE is date-only (no time component)
        // Normalize to start of day to avoid timezone/time issues
        const d = new Date(since);
        d.setUTCHours(0, 0, 0, 0);
        searchCriteria.since = d;
      }
      if (before) {
        const d = new Date(before);
        d.setUTCHours(0, 0, 0, 0);
        searchCriteria.before = d;
      }
      if (unseen) searchCriteria.seen = false;
      if (from) searchCriteria.from = from;

      const messages = [];

      // Search for matching UIDs using IMAP SEARCH
      const hasCriteria = Object.keys(searchCriteria).length > 0;
      const uids = hasCriteria
        ? await client.search(searchCriteria, { uid: true })
        : await client.search({ all: true }, { uid: true });

      // Take the most recent N messages
      const recentUids = uids.slice(-Number(limit));

      for (const uid of recentUids) {
        for await (const msg of client.fetch({ uid }, {
          envelope: true,
          bodyParts: ['text']
        })) {
          const envelope = msg.envelope;
          let text = '';
          if (msg.bodyParts) {
            for (const [, value] of msg.bodyParts) {
              text = value.toString();
            }
          }

          messages.push({
            uid: uid,
            from: envelope.from ? envelope.from.map(a => a.address).join(', ') : '',
            to: envelope.to ? envelope.to.map(a => a.address).join(', ') : '',
            subject: envelope.subject || '',
            date: envelope.date ? envelope.date.toISOString() : '',
            text: text.substring(0, 2000)
          });
        }
      }

      res.json({ emails: messages, total: uids.length });
    } finally {
      lock.release();
    }

    await client.logout();
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Send email via SMTP
app.post('/send-email', async (req, res) => {
  const {
    host, port = 587, user, password,
    to, subject, body, html
  } = req.body;

  if (!host || !user || !password || !to || !subject) {
    return res.status(400).json({ error: 'Missing required fields: host, user, password, to, subject' });
  }

  try {
    const transporter = nodemailer.createTransport({
      host,
      port: Number(port),
      secure: Number(port) === 465,
      auth: { user, pass: password }
    });

    const info = await transporter.sendMail({
      from: user,
      to,
      subject,
      text: body || '',
      html: html || undefined
    });

    res.json({ success: true, messageId: info.messageId });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`email-bridge listening on port ${PORT}`);
});
