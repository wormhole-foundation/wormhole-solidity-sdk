const fs = require("fs");
const path = require("path");
let pkg = require("../package.json");

pkg = Object.assign(pkg, {
  "files": [
    "**/*.sol",
    "README.md"
  ]
})

delete pkg.scripts;

fs.writeFileSync(path.resolve(__dirname, "../contracts/package.json"), JSON.stringify(pkg, null, 2));
