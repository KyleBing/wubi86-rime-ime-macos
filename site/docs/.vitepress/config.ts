import { defineConfig } from 'vitepress'

// 站点挂在 kylebing.cn/wubi/macos/，与日后的 iOS 说明并列。
export default defineConfig({
  title: '玫枫五笔',
  description: 'macOS 原生五笔输入法：自造词、日期时间、快捷键',
  lang: 'zh-CN',
  base: '/wubi/macos/',
  cleanUrls: true,
  lastUpdated: true,
  head: [
    ['link', { rel: 'icon', href: '/wubi/macos/logo.png' }]
  ],
  themeConfig: {
    logo: '/logo.png',
    siteTitle: '玫枫五笔',
    nav: [
      { text: '自造词', link: '/guide/custom-words' },
      { text: '日期时间', link: '/guide/date-time' },
      { text: '快捷键', link: '/guide/shortcuts' }
    ],
    sidebar: [
      {
        text: '开始',
        items: [
          { text: '介绍', link: '/' },
          { text: '安装', link: '/guide/install' }
        ]
      },
      {
        text: '输入',
        items: [
          { text: '自造词', link: '/guide/custom-words' },
          { text: '日期与时间', link: '/guide/date-time' },
          { text: '快捷键', link: '/guide/shortcuts' }
        ]
      },
      {
        text: '更多',
        items: [
          { text: '外观', link: '/guide/appearance' },
          { text: '词库与同步', link: '/guide/lexicon' }
        ]
      }
    ],
    outline: { label: '本页目录', level: [2, 3] },
    docFooter: { prev: '上一页', next: '下一页' },
    lastUpdated: { text: '更新于' },
    search: { provider: 'local' },
    footer: {
      message: '输入引擎 <a href="https://github.com/rime/librime">librime</a> · 码表 <a href="https://github.com/KyleBing/rime-wubi86-jidian">rime-wubi86-jidian</a>',
      copyright: '玫枫五笔 macOS'
    }
  }
})
