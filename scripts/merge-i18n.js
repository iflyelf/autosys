#!/usr/bin/env node
// 生成只含中文的 web/src/lang/zh_cn.js:
//   上游 zh_cn.js + i18n/zh_cn.json 补译词条, 按 en.js 的 key 顺序输出,
//   并把界面里的 Semaphore 品牌与命令统一替换为 autosys。
// 用法: node merge-i18n.js <上游 web/src/lang 目录> <补译 json>
const fs = require('fs');
const path = require('path');

const [langDir, extraFile] = process.argv.slice(2);
if (!langDir || !extraFile) {
  console.error('usage: merge-i18n.js <lang dir> <zh_cn.json>');
  process.exit(1);
}

const load = (f) => Function(fs.readFileSync(f, 'utf8').replace('export default', 'return'))();

const en = load(path.join(langDir, 'en.js'));
const zh = load(path.join(langDir, 'zh_cn.js'));
const extra = JSON.parse(fs.readFileSync(extraFile, 'utf8'));

const brand = (v) => v
  .replace(/Semaphore UI/g, '自动化平台')
  .replace(/信号灯 UI/g, '自动化平台 UI')
  .replace(/信号灯/g, '自动化平台')
  .replace(/Semaphore(?! PRO)/g, '自动化平台')
  .replace(/\bsemaphore (user|runner|setup|server|migrate|project|version)\b/g, 'autosys $1');

const quote = (s) => `'${s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n')}'`;

const out = [];
const missing = [];
Object.keys(en).forEach((key) => {
  let value = extra[key] !== undefined ? extra[key] : zh[key];
  if (typeof value !== 'string' || value.trim() === '') {
    missing.push(key);
    return;
  }
  value = brand(value);
  const k = /^[A-Za-z_$][\w$]*$/.test(key) ? key : quote(key);
  out.push(`  ${k}: ${quote(value)},`);
});

fs.writeFileSync(path.join(langDir, 'zh_cn.js'), `export default {\n${out.join('\n')}\n};\n`);

console.log(`zh_cn: ${out.length}/${Object.keys(en).length} 条中文词条`);
if (missing.length) {
  console.log(`WARN: ${missing.length} 条上游新增词条暂无中文, 界面将回退显示英文:`);
  console.log(`  ${missing.join(' ')}`);
}
