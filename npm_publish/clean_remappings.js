if (process.argv.length !== 4) {
  console.error("Usage: node clean_remappings.js <root dir (containing remappings.txt)> <contracts dir>");
  process.exit(1);
}
const remappingsFilePath = process.argv[2] + "/remappings.txt";
const contractsDir = process.argv[3];

const fs = require("fs");
const path = require("path");

const remappings = fs.readFileSync(remappingsFilePath, "utf8")
  .split("\n")
  .reduce(
    (acc, line) => {
      if (line && !line.startsWith("#")) {
        const [label, target] = line.split("/=");
        if (target.startsWith("src/"))
          acc = { ...acc, [label]: target.slice(4) };
      }
      return acc;
    },
    {}
  );

const findSolFiles = (dir) => fs.readdirSync(dir)
  .reduce(
    (acc, item) => {
      const fullPath = path.join(dir, item);
      const stat = fs.statSync(fullPath);
      if (stat.isDirectory())
        acc.push(...findSolFiles(fullPath));
      else if (stat.isFile() && path.extname(item) === ".sol")
        acc.push(fullPath);
      return acc;
    },
    []
  );

//match plain import statements or starting at from to avoid hassle of parsing multi-line imports
const importRe = /((?:import|from)\s+")([^/]+)\/((?:[^/"]+)\/)*([^.]+\.sol";)/g;

for (const filePath of findSolFiles(contractsDir)) {
  let modified = false;
  const fileContent = fs.readFileSync(filePath, "utf8").replace(importRe, (match, head, label, subdir, tail) => {
    const target = remappings[label];
    if (target !== undefined) {
      modified = true;
      const longPath = path.join(contractsDir, target, subdir ?? "");
      const shortPath = path.relative(path.dirname(filePath), longPath) || ".";
      const finalPath = (shortPath.startsWith(".") ? "" : "./") + shortPath + "/";
      return `${head}${finalPath}${tail}`;
    }
    return match;
  });

  if (modified)
    fs.writeFileSync(filePath, fileContent, "utf8");
}
