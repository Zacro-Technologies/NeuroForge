import Foundation

enum NFAIGenerationStorageError: Error, LocalizedError {
    case capacity

    var errorDescription: String? {
        NFAILearningCopy.text(
            "Your saved AI question sets have reached the storage limit. Remove an unwanted set in generation history, then retry saving this set.",
            "保存したAI問題セットが保存容量の上限に達しました。作成履歴で不要なセットを削除してから、このセットの保存を再試行してください。"
        )
    }
}
