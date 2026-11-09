#import <Foundation/Foundation.h>

/// Turns the chat transcript into a Gemini request body, spending as few input
/// tokens as possible without hurting the coding loop.
///
/// What it does, in order:
///  1. Repairs the transcript so the API never answers 400 for structure reasons
///     (unanswered function calls, orphan function responses, mode switches).
///  2. Drops local-only notices (errors, status) and the synthetic
///     "Tool Call: ..." display text that used to be sent twice.
///  3. When the estimated size passes the budget, shrinks OLD bulky payloads
///     (tool output, file contents inside writeFile/editFile calls) and, if still
///     needed, drops whole old turns. The first user message (the task) is pinned.
///
/// Compaction is monotonic and persisted on the messages (`compacted`/`omitted`)
/// and only happens in steps (at the budget, down to 60% of it). Between steps the
/// request prefix is byte-identical, which is what lets Gemini's implicit caching
/// bill the repeated prefix at a discount. A sliding window recomputed every turn
/// would change the prefix every turn and defeat caching.
@interface AGContextBuilder : NSObject

+ (NSDictionary *)payloadForMessages:(NSArray *)messages
                            pureChat:(BOOL)pureChat
                        systemPrompt:(NSString *)systemPrompt
                      toolDeclarations:(NSArray *)toolDeclarations
                         tokenBudget:(NSUInteger)tokenBudget
                    generationConfig:(NSDictionary *)generationConfig;

/// Rough token estimate (the real tokenizer is not available offline).
+ (NSUInteger)estimateTokensForText:(NSString *)text;

@end
