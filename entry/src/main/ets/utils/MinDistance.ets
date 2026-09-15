/** 编辑距离（用于相似歌曲/歌词匹配） */
export class MinDistance {
  static compute(word1?: string, word2?: string): number {
    if (word1 === undefined || word2 === undefined || word1 === null || word2 === null) {
      return (word1 ? word1.length : 0) + (word2 ? word2.length : 0);
    }
    if (word1.length === 0) {
      return word2.length;
    }
    if (word2.length === 0) {
      return word1.length;
    }

    const rows = word1.length + 1;
    const cols = word2.length + 1;
    const dp: Array<Array<number>> = [];
    for (let i = 0; i < rows; ++i) {
      const row: Array<number> = [];
      for (let j = 0; j < cols; ++j) {
        row.push(Number.POSITIVE_INFINITY);
      }
      dp.push(row);
    }

    for (let i = 0; i <= word1.length; ++i) {
      for (let j = 0; j <= word2.length; ++j) {
        if (i === 0 || j === 0) {
          dp[i][j] = Math.max(i, j);
          continue;
        }
        const c1 = word1.charAt(i - 1);
        const c2 = word2.charAt(j - 1);
        if (c1 === c2) {
          dp[i][j] = Math.min(dp[i - 1][j - 1], dp[i - 1][j] + 1, dp[i][j - 1] + 1);
        } else {
          dp[i][j] = Math.min(dp[i - 1][j - 1] + 1, dp[i - 1][j] + 1, dp[i][j - 1] + 1);
        }
      }
    }
    return dp[word1.length][word2.length];
  }
}
