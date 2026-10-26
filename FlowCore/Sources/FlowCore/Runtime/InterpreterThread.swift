import Foundation

/// Runs one program's tasks on a thread of its own with a large stack.
///
/// Evaluating expressions and checking programs recurse. On Swift's shared threads (512 KB of
/// stack) a long but legitimate expression could overflow and close the app; here the limits
/// enforced by the parser and the reader leave a wide margin. Only the pages actually used
/// take memory.
final class InterpreterThread: TaskExecutor, @unchecked Sendable {
    static let stackSize = 64 << 20

    private let condition = NSCondition()
    private var jobs: [UnownedJob] = []
    private var head = 0
    private var finished = false

    init() {
        // The thread keeps the executor alive until `finish()` lets it end.
        let thread = Thread { [self] in loop() }
        thread.stackSize = Self.stackSize
        thread.qualityOfService = .userInitiated
        thread.name = "FlowCore interpreter"
        thread.start()
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    /// Lets the thread end once the jobs already queued have run.
    func finish() {
        condition.lock()
        finished = true
        condition.signal()
        condition.unlock()
    }

    private func loop() {
        while true {
            condition.lock()
            while head == jobs.count && !finished { condition.wait() }
            if head == jobs.count {
                condition.unlock()
                return
            }
            let job = jobs[head]
            head += 1
            if head > 256 && head * 2 > jobs.count {
                jobs.removeFirst(head)
                head = 0
            }
            condition.unlock()
            job.runSynchronously(on: asUnownedTaskExecutor())
        }
    }
}
