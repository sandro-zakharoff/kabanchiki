package com.kabanchiki.app.core.tracking

import android.content.Context
import com.kabanchiki.app.core.data.JobsRepository
import com.kabanchiki.app.core.data.TasksRepository
import com.kabanchiki.app.core.supabase.ApplicationScope
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Starts/stops the tracking services so they run exactly while there is
 * something live to show: [TaskTrackingService] for a regular task in
 * progress, [JobTrackingService] for a running hourly job. Also applies a
 * leftover offline gap on login (the service may have been killed while the
 * device was offline).
 */
@Singleton
class TrackingController @Inject constructor(
    @ApplicationContext private val context: Context,
    private val tasksRepository: TasksRepository,
    private val jobsRepository: JobsRepository,
    private val offlineGuard: OfflineGuard,
    @ApplicationScope private val scope: CoroutineScope,
) {
    private var job: Job? = null

    fun start() {
        if (job?.isActive == true) return
        job = scope.launch {
            offlineGuard.applyPendingGap()
            combine(tasksRepository.tasks, jobsRepository.stats) { tasks, stats ->
                tasks to stats
            }.collect { (tasks, stats) ->
                val activeTask = tasks.firstOrNull { it.status == "in_progress" }
                if (activeTask != null) {
                    TaskTrackingService.start(context, activeTask.id)
                } else {
                    TaskTrackingService.stop(context)
                }

                val runningJob = stats.firstOrNull { it.runningSince != null }
                if (runningJob != null) {
                    JobTrackingService.start(context, runningJob.jobId)
                } else {
                    JobTrackingService.stop(context)
                }
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        TaskTrackingService.stop(context)
        JobTrackingService.stop(context)
    }
}
