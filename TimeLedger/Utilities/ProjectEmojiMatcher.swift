import Foundation

enum ProjectEmojiMatcher {
    private static let rules: [(keywords: [String], emoji: String)] = [
        (["写作", "写材料", "写稿", "文章", "博客", "文档"], "✍️"),
        (["阅读", "读书", "看书", "学习", "研究", "课程", "英语", "考试"], "📚"),
        (["会议", "开会", "沟通", "面试", "电话", "通话"], "💬"),
        (["编程", "开发", "代码", "程序", "调试", "修 bug", "bug"], "💻"),
        (["设计", "UI", "UX", "画", "原型"], "🎨"),
        (["运动", "跑步", "健身", "锻炼", "游泳", "骑行", "散步", "走路"], "🏃"),
        (["吃饭", "午餐", "晚餐", "早餐", "做饭", "餐饮", "喝咖啡", "咖啡"], "🍽"),
        (["睡眠", "睡觉", "休息", "午睡"], "😴"),
        (["通勤", "地铁", "公交", "开车", "出行", "旅行", "出差"], "🚇"),
        (["家务", "打扫", "洗衣", "收纳", "购物"], "🏠"),
        (["孩子", "带娃", "育儿", "陪读"], "👶"),
        (["音乐", "练琴", "听歌", "吉他", "钢琴"], "🎵"),
        (["电影", "追剧", "视频", "游戏", "娱乐"], "🎬"),
        (["冥想", "正念", "日记", "复盘", "思考", "计划"], "🧠"),
        (["工作", "办公", "邮件", "汇报", "项目"], "💼"),
        (["医疗", "看病", "医院", "吃药"], "🏥"),
        (["财务", "记账", "理财", "报销"], "💰"),
        (["未知"], "❓"),
    ]

    private static let fallbackPool = [
        "⭐️", "🔹", "📌", "✨", "🍀", "🎯", "🧩", "📎", "🌙", "☀️",
        "🔥", "💧", "🌿", "🦋", "🎈", "🔑", "📦", "🧭", "🪄", "🪨",
    ]

    static func emoji(for name: String, categoryName: String = "") -> String {
        let haystack = "\(name) \(categoryName)".lowercased()
        for rule in rules {
            if rule.keywords.contains(where: { haystack.contains($0.lowercased()) }) {
                return rule.emoji
            }
        }
        return stableFallback(for: name)
    }

    private static func stableFallback(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "📌" }
        var hash: UInt64 = 5381
        for scalar in trimmed.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        let index = Int(hash % UInt64(fallbackPool.count))
        return fallbackPool[index]
    }
}
