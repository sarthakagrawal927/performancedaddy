import { createHash } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import release from './release.json' with { type: 'json' };

if (!/^[a-f0-9]{64}$/.test(release.sha256) ||
    !/^[a-f0-9]{40}$/.test(release.sourceSha) ||
    !/^https:\/\/[^/]+\/updates\/$/.test(release.baseUrl) ||
    !/^[A-Za-z0-9.-]+\.dmg$/.test(release.filename) ||
    !Number.isSafeInteger(release.bytes) || release.bytes < 1 ||
    !Number.isSafeInteger(release.build) || release.build < 1) {
  throw new Error('A qualified Sparkle release manifest is required');
}

const asset = new URL(`./public/updates/${release.filename}`, import.meta.url);
const feed = await readFile(new URL('./public/updates/appcast.xml', import.meta.url), 'utf8');
if ((await stat(asset)).size !== release.bytes ||
    createHash('sha256').update(await readFile(asset)).digest('hex') !== release.sha256 ||
    !feed.includes(`url="${release.baseUrl}${release.filename}"`) ||
    !feed.includes(`length="${release.bytes}"`) ||
    !feed.includes(`<sparkle:version>${release.build}</sparkle:version>`) ||
    !feed.includes(`<sparkle:shortVersionString>${release.version}</sparkle:shortVersionString>`)) {
  throw new Error('Sparkle feed and DMG do not match the qualified release');
}

console.log('Qualified Sparkle feed and DMG match the release manifest.');
