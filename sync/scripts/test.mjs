import { readdirSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
// Wrangler 3's old workerd runner cannot register two test-file workers together.
// Each file gets a fresh runtime; do not change the production toolchain to work around it.
// Guard against a silent pass: a wrong directory would otherwise run nothing and exit 0.
const MIN_TEST_FILES = 6
const files = readdirSync(new URL('../tests', import.meta.url)).filter(name=>name.endsWith('.test.ts')).sort()
if (files.length < MIN_TEST_FILES) {
  console.error(`Expected at least ${MIN_TEST_FILES} test files, found ${files.length}`)
  process.exit(1)
}
let ran = 0
for (const file of files) {
  const result=spawnSync('node_modules/.bin/vitest',['run',`tests/${file}`],{stdio:'inherit',cwd:new URL('..', import.meta.url)})
  if(result.error)throw result.error
  if(result.status!==0)process.exit(result.status??1)
  ran++
}
console.log(`sumi-sync: ${ran}/${files.length} test files passed`)
