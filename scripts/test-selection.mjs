import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

// Exercise the actual handler body with a service stub; no desktop or receiver needed.
const qml = readFileSync(new URL("../widget/LocalSendBar.qml", import.meta.url), "utf8");
const handler = qml.match(/    function selectPaths\(payload: string\): string \{([\s\S]*?)\n    \}/);
assert.ok(handler, "selectPaths handler must exist");
const root = {
  localsend: {
    ready: true, selectedPaths: ["/previous"], payloadKind: "clipboard",
    baseName: path => path.split("/").pop(),
  },
  open() { this.opened = true; },
};
const select = payload => runInNewContext(
  `(function(payload) {${handler[1]} })(payload)`, { root, payload },
);
for (const payload of ["bad JSON", "null", "{}", '{"paths":[]}',
  '{"paths":["relative"]}', '{"paths":["/valid",3]}', '{"paths":["/bad\\u0000path"]}']) {
  assert.notEqual(select(payload), "ok");
  assert.deepEqual(root.localsend.selectedPaths, ["/previous"]);
  assert.equal(root.localsend.payloadKind, "clipboard");
  assert.equal(root.opened, undefined);
}
root.localsend.ready = false;
assert.equal(select('{"paths":["/file"]}'), "LocalSend receiver is not ready");
root.localsend.ready = true;
const paths = ['/space and "quote".txt', "/line\nbreak", "/folder"];
assert.equal(select(JSON.stringify({ paths })), "ok");
assert.deepEqual(Array.from(root.localsend.selectedPaths), paths);
assert.equal(root.localsend.payloadKind, "files");
assert.equal(root.localsend.payloadLabel, "3 items selected");
assert.equal(root.opened, true);
assert.equal(select('{"paths":["/folder/file.txt"]}'), "ok");
assert.equal(root.localsend.payloadLabel, "file.txt");
console.log("PASS: selection validation, atomic rejection, readiness, and panel handoff");
