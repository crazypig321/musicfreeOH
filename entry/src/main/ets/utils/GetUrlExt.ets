/** 从 url 中提取扩展名（移植自 getUrlExt.ts） */
export class GetUrlExt {
  static get(url?: string): string {
    if (url === undefined || url === null || url.length === 0) {
      return '';
    }
    // 去掉 query 和 fragment
    let path = url;
    const qIdx = path.indexOf('?');
    if (qIdx !== -1) {
      path = path.substring(0, qIdx);
    }
    const hIdx = path.indexOf('#');
    if (hIdx !== -1) {
      path = path.substring(0, hIdx);
    }
    const lastSlash = path.lastIndexOf('/');
    const fileName = lastSlash === -1 ? path : path.substring(lastSlash + 1);
    const lastDot = fileName.lastIndexOf('.');
    if (lastDot === -1 || lastDot === 0) {
      return '';
    }
    return fileName.substring(lastDot).toLowerCase();
  }
}
