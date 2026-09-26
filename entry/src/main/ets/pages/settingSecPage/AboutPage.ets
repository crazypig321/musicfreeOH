import { CommonNav, titleBarOf } from '../../view/CommonNav';
import { appState } from '../../entryability/AppState';
import { AppMeta } from '../../core/AppMeta';
import { BarScrollHelper, IsApiVersion_24 } from '../../utils/BarScrollHelper';
import { DialogManager } from '../../utils/DialogUtils';
import { WebUtils } from '../../utils/WebUtils';
import { HttpClient } from '../../infra/HttpClient';
import { MenuUtils } from '../../utils/MenuUtils';
import { MenuItemParams } from '../../view/CommonCom';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { ContextHolder } from '../../common/ContextHolder';
import { PathConst } from '../../common/PathConst';
import { FileUtils } from '../../utils/FileUtils';

/** 仓库地址常量 */
const REPO_OH: string = 'https://github.com/crazypig321/musicfreeOH.git';
const REPO_ORIGIN: string = 'https://github.com/maotoumao/MusicFree.git';
const DEV_HOME: string = 'https://github.com/crazypig321';
const DEP_DATE_URL: string = 'https://ohpm.openharmony.cn/#/cn/detail/@xiaoye%2Fdate';
const DEP_COLOR_PICKER_URL: string = 'https://ohpm.openharmony.cn/#/cn/detail/@keke%2Fcolor-picker';
/** GitHub 最新 release 接口与发布页 */
const RELEASE_API_URL: string = 'https://api.github.com/repos/crazypig321/musicfreeOH/releases/latest';
const RELEASE_PAGE_URL: string = 'https://github.com/crazypig321/musicfreeOH/releases/latest';
/** 国内加速前缀型代理（拼接在目标 URL 前），依次回退尝试 */
const GH_PROXY_PREFIXES: Array<string> = ['https://gh-proxy.com/', 'https://ghfast.top/'];
/** 国内换域型浏览镜像（github.com → kkgithub.com） */
const GH_MIRROR_PAGE_URL: string = 'https://kkgithub.com/crazypig321/musicfreeOH/releases/latest';
/** 更新标签菜单锚点 id */
const UPDATE_TAG_ANCHOR_ID: string = 'about_update_tag';

/** GitHub latest release 接口返回体（仅声明所需字段） */
interface ReleaseRaw {
  tag_name?: string;
  assets?: Array<ReleaseAssetRaw>;
}

/** release 资产原始字段 */
interface ReleaseAssetRaw {
  name?: string;
  browser_download_url?: string;
}

/** 归一化后的 release 软件包资产 */
class ReleaseAsset {
  name: string = '';
  url: string = '';
}

/** 从 release 资产中选取软件包：优先 .hap，其次第一个有效资产；无资产返回 null */
function pickReleaseAsset(release: ReleaseRaw): ReleaseAsset | null {
  const assets = release.assets;
  if (assets === undefined) {
    return null;
  }
  let fallback: ReleaseAsset | null = null;
  for (const raw of assets) {
    const name = raw.name;
    const url = raw.browser_download_url;
    if (typeof name !== 'string' || name.length === 0 || typeof url !== 'string' || url.length === 0) {
      continue;
    }
    const asset = new ReleaseAsset();
    asset.name = name;
    asset.url = url;
    if (fallback === null) {
      fallback = asset;
    }
    if (name.toLowerCase().endsWith('.hap')) {
      return asset;
    }
  }
  return fallback;
}

/** 比较语义化版本号（忽略 v 前缀与非数字字符，逐段比较）：a 是否大于 b */
function isNewerVersion(a: string, b: string): boolean {
  const parse = (v: string): Array<number> => {
    const parts: Array<number> = [];
    const segs = v.replace(/^[vV]/, '').split('.');
    for (const seg of segs) {
      const digits = seg.replace(/[^0-9]/g, '');
      const n = digits.length > 0 ? Number(digits) : 0;
      parts.push(Number.isFinite(n) ? n : 0);
    }
    return parts;
  };
  const pa = parse(a);
  const pb = parse(b);
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const x = i < pa.length ? pa[i] : 0;
    const y = i < pb.length ? pb[i] : 0;
    if (x !== y) {
      return x > y;
    }
  }
  return false;
}

/** 关于页条目行：头像/图标 + 标题 + 右侧说明 + chevron，可选点击行为 */
interface AboutRow {
  /** 头像图片（设置后优先于 icon 显示） */
  avatar?: Resource;
  /** SymbolGlyph 图标 */
  icon: Resource;
  title: string;
  /** 右侧说明文字 */
  trailing?: string;
  /** 右侧说明是否按长文本（地址）省略 */
  trailingEllipsis?: boolean;
  showChevron?: boolean;
  action?: () => void;
}

/** 关于页分组：标题 + 卡片内多行 */
interface AboutSection {
  title: string;
  rows: Array<AboutRow>;
}

/**
 * 关于页面：应用图标/名称/版本 + 开发者 + 项目地址 + 开源与条款 + 三方库
 * 从设置页「关于」条目进入
 */
@ComponentV2
export struct AboutPage {
  scroller: Scroller = new Scroller();
  /** GitHub 最新 release 版本号；为空表示无需更新（标签不展示） */
  @Local latestVersion: string = '';

  aboutToAppear(): void {
    this.checkUpdate();
  }

  /** 拉取 GitHub 最新 release 信息：直连不通时依次走国内代理；全部失败返回 null */
  private async fetchLatestRelease(): Promise<ReleaseRaw | null> {
    const headers: Record<string, string> = {
      'User-Agent': 'musicfreeOH',
      'Accept': 'application/vnd.github+json'
    };
    const urls: Array<string> = [RELEASE_API_URL];
    for (const prefix of GH_PROXY_PREFIXES) {
      urls.push(prefix + RELEASE_API_URL);
    }
    for (const url of urls) {
      const result = await HttpClient.get(url, headers, 6000);
      if (result === null || result.statusCode !== 200) {
        continue;
      }
      try {
        const raw = JSON.parse(result.body) as ReleaseRaw;
        const tag = raw.tag_name;
        if (typeof tag === 'string' && tag.length > 0) {
          return raw;
        }
      } catch (e) {
        // 当前源解析失败，尝试下一个
      }
    }
    return null;
  }

  /** 进入页面静默检查更新：最新版本高于本地时记录，供版本号旁标签展示 */
  private async checkUpdate(): Promise<void> {
    const raw = await this.fetchLatestRelease();
    if (raw === null) {
      return;
    }
    const tag = raw.tag_name;
    if (tag !== undefined && isNewerVersion(tag, AppMeta.appVersion)) {
      this.latestVersion = tag;
    }
  }

  /** 「检查更新」条目点击：有新版本时选择存放位置并下载软件包 */
  private async doCheckUpdate(): Promise<void> {
    this.showToast('正在检查更新…');
    const release = await this.fetchLatestRelease();
    if (release === null) {
      this.showToast('检查更新失败，请稍后重试');
      return;
    }
    const tag = release.tag_name;
    if (tag === undefined || !isNewerVersion(tag, AppMeta.appVersion)) {
      this.showToast('当前已是最新版本');
      return;
    }
    this.latestVersion = tag;
    const asset = pickReleaseAsset(release);
    if (asset === null) {
      this.showToast('发布页未提供软件包，请到发布页查看');
      return;
    }
    this.pickSaveLocationAndDownload(asset);
  }

  /** 弹出系统保存器选择存放位置（同备份导出），确认后下载软件包写入 */
  private pickSaveLocationAndDownload(asset: ReleaseAsset): void {
    try {
      const documentPicker = new picker.DocumentViewPicker(ContextHolder.get());
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [asset.name];
      documentPicker.save(options).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        this.downloadUpdate(asset, uris[0]);
      }).catch((_e: Object): void => {
        this.showToast('保存文件失败');
      });
    } catch (error) {
      this.showToast('无法打开文件保存器');
    }
  }

  /** 下载软件包：直连不通时依次走国内代理，经缓存目录中转写入保存位置 */
  private async downloadUpdate(asset: ReleaseAsset, destUri: string): Promise<void> {
    this.showToast('正在下载新版本…');
    const tempPath = PathConst.cachePath + 'update_' + Date.now().toString() + '_' + asset.name;
    const urls: Array<string> = [asset.url];
    for (const prefix of GH_PROXY_PREFIXES) {
      urls.push(prefix + asset.url);
    }
    const headers: Record<string, string> = { 'User-Agent': 'musicfreeOH' };
    let ok = false;
    for (const url of urls) {
      ok = await HttpClient.downloadToFile(url, tempPath, headers, undefined, undefined, undefined, 300000);
      if (ok) {
        break;
      }
    }
    if (!ok) {
      FileUtils.unlink(tempPath);
      this.showToast('下载失败，请稍后重试');
      return;
    }
    try {
      const src = fs.openSync(tempPath, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(destUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dst.fd);
      } finally {
        fs.closeSync(src);
        fs.closeSync(dst);
      }
      this.showToast('新版本 ' + asset.name + ' 已保存');
    } catch (e) {
      this.showToast('保存文件失败');
    } finally {
      FileUtils.unlink(tempPath);
    }
  }

  /** 点击更新标签：弹出菜单选择发布页打开方式（官方/国内代理/镜像） */
  private openUpdateMenu(): void {
    const items: Array<MenuItemParams> = [];
    const official = new MenuItemParams();
    official.label = 'GitHub 官方';
    official.onAction = (): void => {
      MenuUtils.Dismiss();
      this.openWeb(RELEASE_PAGE_URL);
    };
    items.push(official);
    for (const prefix of GH_PROXY_PREFIXES) {
      const item = new MenuItemParams();
      item.label = '国内代理 ' + prefix.replace(/^https?:\/\//, '').replace(/\/$/, '');
      item.onAction = (): void => {
        MenuUtils.Dismiss();
        this.openWeb(prefix + RELEASE_PAGE_URL);
      };
      items.push(item);
    }
    const mirror = new MenuItemParams();
    mirror.label = '镜像站 kkgithub';
    mirror.onAction = (): void => {
      MenuUtils.Dismiss();
      this.openWeb(GH_MIRROR_PAGE_URL);
    };
    items.push(mirror);
    MenuUtils.Open(this.getUIContext(), UPDATE_TAG_ANCHOR_ID, items, {
      placement: Placement.Bottom
    });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // TODO: Implement error handling.
    }
  }

  /** 拉起系统浏览器打开网址 */
  private openWeb(url: string): void {
    WebUtils.open(url, (message: string): void => {
      this.showToast(message);
    });
  }

  /** 分组数据 */
  private sections(): Array<AboutSection> {
    return [
      {
        title: '开发者',
        rows: [
          {
            avatar: $r('app.media.crazypig321'),
            icon: $r('sys.symbol.person'),
            title: 'crazypig321',
            showChevron: true,
            action: (): void => {
              this.openWeb(DEV_HOME);
            }
          }
        ]
      },
      {
        title: '项目地址',
        rows: [
          {
            icon: $r('sys.symbol.store'),
            title: '项目仓库',
            trailing: REPO_OH,
            trailingEllipsis: true,
            action: (): void => {
              this.openWeb(REPO_OH);
            }
          },
          {
            icon: $r('sys.symbol.store'),
            title: '原项目仓库',
            trailing: REPO_ORIGIN,
            trailingEllipsis: true,
            action: (): void => {
              this.openWeb(REPO_ORIGIN);
            }
          }
        ]
      },
      {
        title: '软件版本',
        rows: [
          {
            icon: $r('sys.symbol.download'),
            title: '检查更新',
            trailing: '当前 ' + AppMeta.appVersion,
            showChevron: true,
            action: (): void => {
              this.doCheckUpdate();
            }
          }
        ]
      },
      {
        title: '开源与条款',
        rows: [
          {
            icon: $r('sys.symbol.doc_plaintext'),
            title: '开源许可',
            trailing: 'AGPL-3.0 协议'
          },
          {
            icon: $r('sys.symbol.info_circle'),
            title: '免责声明',
            showChevron: true,
            action: (): void => {
              DialogManager.OpenDialog('免责声明');
            }
          }
        ]
      },
      {
        title: '三方库',
        rows: [
          {
            icon: $r('sys.symbol.store'),
            title: '@xiaoye/date',
            trailing: '1.0.1',
            showChevron: true,
            action: (): void => {
              this.openWeb(DEP_DATE_URL);
            }
          },
          {
            icon: $r('sys.symbol.store'),
            title: '@keke/color-picker',
            trailing: '1.0.4',
            showChevron: true,
            action: (): void => {
              this.openWeb(DEP_COLOR_PICKER_URL);
            }
          }
        ]
      }
    ];
  }

  /** 单行条目：头像/图标 + 标题 + 右侧说明 + chevron */
  @Builder
  private RowItem(row: AboutRow) {
    Row({ space: 12 }) {
      if (row.avatar) {
        Image(row.avatar)
          .width(44)
          .height(44)
          .borderRadius(22)
      } else {
        SymbolGlyph(row.icon)
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      Text(row.title)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      if (row.trailing) {
        Text(row.trailing)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: row.trailingEllipsis ? '50%' : '100%' })
      }
      if (row.showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.icon_tertiary')])
      }
    }
    .width('100%')
    .height(52)
    .onClick(() => {
      const action = row.action;
      if (action) {
        action();
      }
    })
  }

  build() {
    CommonNav({
      titleBarOp: titleBarOf('关于'),
      scroller: this.scroller,
      doubleTapToTop: true
    }) {
      Stack({ alignContent: Alignment.Top }) {
        List({ scroller: this.scroller, space: 12 }) {
          // 头部：应用图标 + 软件名 + 版本
          ListItem() {
            Column({ space: 10 }) {
              Stack() {
                Image($r('app.media.background'))
                  .width(76)
                  .height(76)
                Image($r('app.media.foreground'))
                  .width(76)
                  .height(76)
              }
              .width(76)
              .height(76)
              .borderRadius(18)
              .clip(true)

              Text('MusicFreeOH')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
              Row({ space: 6 }) {
                Text('当前版本 ' + AppMeta.appVersion)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                if (this.latestVersion.length > 0) {
                  Text('新版本 ' + this.latestVersion)
                    .fontSize(10)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .padding({ top: 3, bottom: 3, left: 5, right: 5 })
                    .borderRadius(3)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .id(UPDATE_TAG_ANCHOR_ID)
                    .onClick(() => {
                      this.openUpdateMenu();
                    })
                }
              }
              Text('移植自猫头猫的开源项目 MusicFree')
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .margin({ top: 24, bottom: 8 })
            .alignItems(HorizontalAlign.Center)
          }

          // 分组：标题 + 卡片
          ForEach(this.sections(), (section: AboutSection) => {
            ListItem() {
              Text(section.title)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
            }
            ListItem() {
              Column() {
                ForEach(section.rows, (row: AboutRow, index: number) => {
                  Column() {
                    this.RowItem(row)
                    if (index < section.rows.length - 1) {
                      Divider()
                        .DividerStyle()
                    }
                  }
                  .width('100%')
                }, (row: AboutRow) => row.title)
              }
              .width('100%')
            }
            .ListItemStyle()
          }, (section: AboutSection) => section.title)
        }
        .ListStyle()
        .onScrollFrameBegin((offset: number) => {
          BarScrollHelper.notifyScrollDelta(this.getUIContext(), offset)
          return { offsetRemain: offset }
        })
      }
    }
  }
}

@Extend(ListItem)
function ListItemStyle() {
  .width('100%')
  .borderRadius(16)
  .padding(12)
  .backgroundColor($r('sys.color.comp_background_list_card'))
}

@Extend(Divider)
function DividerStyle() {
  .color($r('sys.color.comp_divider'))
  .margin({ left: 32, right: 4 })
}

@Extend(List)
function ListStyle() {
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.Spring)
  .contentStartOffset(appState.topRect + 66)
  .contentEndOffset(appState.bottomRect + (IsApiVersion_24() && appState.hdsBarLayoutMode === 1 ? 130 : 60))
  .padding({ left: 16, right: 16 })
}
