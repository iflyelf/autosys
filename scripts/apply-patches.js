#!/usr/bin/env node
// 在上游 semaphore 源码上应用 autosys 定制:
//   1. 仅保留中文界面 (en.js 只作为缺失词条的隐藏回退)
//   2. 品牌 / 命令名改为 autosys (自动化平台)
//   3. 默认时区 Asia/Shanghai, 默认路径改为 /etc/autosys 等
// 每处替换都要求命中, 上游改动导致不匹配时直接失败, 避免静默漏改。
// 用法: node apply-patches.js <上游源码目录>
const fs = require('fs');
const path = require('path');

const src = process.argv[2];
if (!src) {
  console.error('usage: apply-patches.js <semaphore src dir>');
  process.exit(1);
}

let failed = 0;

function patch(file, rules) {
  const f = path.join(src, file);
  let text = fs.readFileSync(f, 'utf8');
  rules.forEach(([from, to]) => {
    const hit = typeof from === 'string' ? text.includes(from) : from.test(text);
    if (!hit) {
      console.error(`ERROR: ${file}: 未匹配 ${from}`);
      failed += 1;
      return;
    }
    text = typeof from === 'string' ? text.split(from).join(to) : text.replace(from, to);
  });
  fs.writeFileSync(f, text);
  console.log(`patched ${file}`);
}

// ---------- 1. 仅保留中文 ----------
const langDir = path.join(src, 'web/src/lang');
fs.readdirSync(langDir)
  .filter((f) => f.endsWith('.js') && !['index.js', 'en.js', 'zh_cn.js'].includes(f))
  .forEach((f) => fs.unlinkSync(path.join(langDir, f)));

const flagDir = path.join(src, 'web/public/flags');
fs.readdirSync(flagDir)
  .filter((f) => f !== 'zh_cn.svg')
  .forEach((f) => fs.unlinkSync(path.join(flagDir, f)));

// 语言菜单只列出中文
patch('web/src/App.vue', [
  [/const LANGUAGES = \{[\s\S]*?\n\};/, "const LANGUAGES = {\n  zh_cn: {\n    title: '中文(大陆)',\n  },\n};"],
  ["    lang = 'en';", "    lang = 'zh_cn';"],
  ["return getLangInfo(locale || 'en');", "return getLangInfo(locale || 'zh_cn');"],
  [/ {8}\{\n {10}id: '',\n {10}flag: getSystemLang\(\)\.flag,\n {10}title: 'System',\n {8}\},\n/, ''],
]);

// 界面语言固定为中文; en 仍保留在 messages 中, 只用于缺失词条回退
patch('web/src/plugins/i18.js', [
  [/let locale = localStorage\.getItem\('lang'\);\n\nif \(!locale\) \{\n[^\n]*\n\}\n/, "const locale = 'zh_cn';\n"],
]);

// lang/index.js 会把所有 lang/*.js 列为可选语言, 这里排除 en
patch('web/src/lang/index.js', [
  ['const languages = Object.keys(messages);', "const languages = Object.keys(messages).filter((lang) => lang !== 'en');"],
]);

// ---------- 2. 品牌与命令名 ----------
patch('web/public/index.html', [
  ['<html lang="en">', '<html lang="zh-CN">'],
  ['<title>Dashboard - Semaphore UI</title>', '<title>自动化平台</title>'],
]);

patch('web/src/views/Auth.vue', [
  ['semaphore user add', 'autosys user add'],
]);

patch('web/src/views/Runners.vue', [
  [/semaphore runner /g, 'autosys runner '],
]);

patch('cli/cmd/root.go', [
  ['Use:   "semaphore",', 'Use:   "autosys",'],
  ['Short: "Semaphore UI is a beautiful web UI for Ansible",', 'Short: "autosys 自动化平台 (基于 Semaphore UI)",'],
  ['fmt.Printf("Semaphore %v\\n", util.Version())', 'fmt.Printf("autosys %v\\n", util.Version())'],
]);

patch('util/config.go', [
  ['env:"SEMAPHORE_SCHEDULE_TIMEZONE" default:"UTC"', 'env:"SEMAPHORE_SCHEDULE_TIMEZONE" default:"Asia/Shanghai"'],
  ['"/usr/local/etc/semaphore/', '"/usr/local/etc/autosys/'],
  ['"/etc/semaphore/', '"/etc/autosys/'],
  ['exec.LookPath("semaphore")', 'exec.LookPath("autosys")'],
]);

patch('cli/setup/setup.go', [
  ['configDirectory = "/etc/semaphore"', 'configDirectory = "/etc/autosys"'],
  ['filepath.Join(configDirectory, "semaphore")', 'filepath.Join(configDirectory, "autosys")'],
  ['filepath.Join(os.TempDir(), "semaphore")', 'filepath.Join(os.TempDir(), "autosys")'],
]);

// 演示项目的中文说明
patch('api/projects/projects.go', [
  ['"Pings the website to provide a real-world example of using Semaphore."', '"此任务 ping 网站, 演示 自动化平台 的真实用法。"'],
  ['"Creates a demo artifact and stores it in the cache."', '"创建演示构建产物并存入缓存。"'],
]);

// ---------- 3. 容器启动脚本 ----------
patch('deployment/docker/server/server-wrapper', [
  [/\/etc\/semaphore/g, '/etc/autosys'],
  [/\/var\/lib\/semaphore/g, '/var/lib/autosys'],
  [/\/tmp\/semaphore/g, '/tmp/autosys'],
  [/\/usr\/local\/bin\/semaphore/g, '/usr/local/bin/autosys'],
  ['${SEMAPHORE_DB:-semaphore}', '${SEMAPHORE_DB:-autosys}'],
  ['"Executing semaphore setup"', '"Executing autosys setup"'],
  ['"Starting semaphore server"', '"Starting autosys server"'],
]);

if (failed) {
  console.error(`共 ${failed} 处补丁未命中, 上游代码可能已变更, 请更新 scripts/apply-patches.js`);
  process.exit(1);
}
console.log('所有补丁已应用');
