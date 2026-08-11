# git使用规范

AI 的改动一律先 commit 再交付审核，commit message 以 [ds] 开头（如"[ds] 修订相遇片段"）；用户可能在此基础上自行修改并另行 commit，若发现用户改动尚未提交，提醒用户。每次动工前检查 git log/status 确认基线。