'use strict';

// Creates the first manager account. Manager accounts are intentionally not
// obtainable through the website — there is no self-service path to the role
// that can read every job in the system. This CLI (run by someone with shell
// access to the server) bootstraps the first one; every manager after that is
// created from inside the console by an existing manager.
//
//   npm run create-manager -- "Grace Molefe" grace@example.com "+27 82 555 0100"
//
// The password is read from the terminal, never from an argument, so it does
// not end up in shell history or the process list.

const readline = require('node:readline');
const { get, run } = require('../db');
const { migrate } = require('../migrate');
const { hashPassword } = require('../auth');
const { passwordProblems, describePasswordPolicy } = require('../security');
const audit = require('../audit');

/** Prompt without echoing what is typed. */
function askHidden(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    const { output } = rl;
    let muted = false;

    const originalWrite = output.write.bind(output);
    output.write = (chunk, ...rest) => {
      if (muted) return true;
      return originalWrite(chunk, ...rest);
    };

    rl.question(question, (answer) => {
      muted = false;
      output.write = originalWrite;
      output.write('\n');
      rl.close();
      resolve(answer);
    });
    muted = true;
  });
}

function ask(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

async function main() {
  migrate({ quiet: true });

  const [argName, argEmail, argPhone] = process.argv.slice(2);

  const fullName = argName || (await ask('Full name: '));
  const email = (argEmail || (await ask('Email: '))).toLowerCase();
  const phone = argPhone || (await ask('Phone: '));

  if (!fullName || !email || !phone) {
    console.error('Name, email and phone are all required.');
    process.exit(1);
  }
  if (get('SELECT id FROM users WHERE email = ?', email)) {
    console.error(`An account already exists for ${email}.`);
    process.exit(1);
  }

  console.log(`\nPassword policy: ${describePasswordPolicy()}\n`);
  const password = await askHidden('Password (not shown): ');
  const confirm = await askHidden('Confirm password: ');

  if (password !== confirm) {
    console.error('Passwords do not match.');
    process.exit(1);
  }

  const problems = passwordProblems(password, { email, fullName });
  if (problems.length) {
    console.error(`Password must ${problems.join(', ')}.`);
    process.exit(1);
  }

  const { lastInsertRowid } = run(
    `INSERT INTO users (role, full_name, email, phone, password_hash, password_changed_at)
     VALUES ('manager', ?, ?, ?, ?, datetime('now'))`,
    fullName,
    email,
    phone,
    await hashPassword(password)
  );

  audit.record({
    actor: null,
    action: audit.ACTIONS.MANAGER_CREATED,
    subjectType: 'user',
    subjectId: Number(lastInsertRowid),
    detail: `${email} (created via CLI)`,
  });

  console.log(`\nManager account created for ${email}.`);
  console.log(
    'On first sign-in they must enrol two-factor authentication before the console will do anything.'
  );
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
