const fs = require('fs');
const path = require('path');

const SRC_DIR = path.join(__dirname, '../contracts'); // Adjust the path if necessary

// Define remappings
const remappings = {
  'wormhole-sdk/': SRC_DIR, // 'wormhole-sdk/' remaps to 'src/'
  'IERC20/': path.join(SRC_DIR, 'interfaces', 'token'), // 'IERC20/' remaps to 'src/interfaces/token/'
};

function processDirectory(dir) {
  fs.readdir(dir, (err, files) => {
    if (err) {
      console.error(`Error reading directory ${dir}:`, err);
      return;
    }

    files.forEach((file) => {
      const filepath = path.join(dir, file);

      fs.stat(filepath, (err, stats) => {
        if (err) {
          console.error(`Error stating file ${filepath}:`, err);
          return;
        }

        if (stats.isDirectory()) {
          processDirectory(filepath);
        } else if (stats.isFile() && path.extname(file) === '.sol') {
          processFile(filepath);
        }
      });
    });
  });
}

function processFile(filePath) {
  fs.readFile(filePath, 'utf8', (err, data) => {
    if (err) {
      console.error(`Error reading file ${filePath}:`, err);
      return;
    }

    let hasMatch = false;
    let newData = data;

    // Process each remapping
    for (const [remapPrefix, remapTarget] of Object.entries(remappings)) {
      // Create a dynamic regex for each remapping
      const importRegex = new RegExp(
          `import\\s+(?:(\\{[\\s\\S]*?\\})\\s+from\\s+)?["']${remapPrefix}([^"']+)["'];`,
          'g'
      );

      newData = newData.replace(importRegex, (match, importItems, importPath) => {
        hasMatch = true;
        const absoluteImportPath = path.join(remapTarget, importPath);
        let relativeImportPath = path.relative(path.dirname(filePath), absoluteImportPath).replace(/\\/g, '/');

        // Ensure the path starts with './' or '../'
        if (!relativeImportPath.startsWith('.')) {
          relativeImportPath = './' + relativeImportPath;
        }

        if (importItems) {
          return `import ${importItems} from "${relativeImportPath}";`;
        } else {
          return `import "${relativeImportPath}";`;
        }
      });
    }

    if (hasMatch) {
      fs.writeFile(filePath, newData, 'utf8', (err) => {
        if (err) {
          console.error(`Error writing file ${filePath}:`, err);
        } else {
          console.log(`Updated imports in ${filePath}`);
        }
      });
    }
  });
}

// Start processing from the SRC_DIR
processDirectory(SRC_DIR);
