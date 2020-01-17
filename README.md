# install node.js
Install nodejs into `/usr/nodejs`
* also install `yarn` & `pnpm`
* auto configure yarn & npm to use `/usr/nodejs`, prevent them using `/usr/local/bin`
* create & append required environment variables
* rebuild global dependencies

# Support
support: **64BIT ONLY** linux & cygwin & Mac OS & WSL

dependencies: wget & xz & sed & sort & grep  
**and standard gnu-utils on Mac**

# Usage
**latest:**
```bash
wget --quiet -O - https://raw.githubusercontent.com/GongT/install-nodejs/master/install.sh | bash -s -
```

also can upgrade node to latest stable version.

**any major version: (0.x not supported)**
```bash
wget --quiet -O - https://raw.githubusercontent.com/GongT/install-nodejs/master/install.sh | bash -s - 12
```
