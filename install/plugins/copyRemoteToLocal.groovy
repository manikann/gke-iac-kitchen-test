import groovy.json.JsonSlurper
import groovy.transform.Field
import org.artifactory.fs.ItemInfo
import org.artifactory.repo.RepoPathFactory

@Field final String CONFIG_PATH = "plugins/copyRemoteToLocal.json"
@Field final Object JSON_CONFIG = new JsonSlurper().parse(new File(ctx.artifactoryHome.haAwareEtcDir, CONFIG_PATH))

log.warn "copyRemoteToLocal: config: {}", JSON_CONFIG

storage {
    log.warn "copyRemoteToLocal: config: {}", JSON_CONFIG
    afterCreate { item ->
        log.warn "copyRemoteToLocal: About to process '{}' '{}' '{}'", item.repoKey, item.repoPath.repoKey, item
        def localRepoName = item.repoPath.file ? JSON_CONFIG[item.repoPath.repoKey] : null
        if (localRepoName) {
            asSystem {
                copyItemToLocalRepo(item, localRepoName)
            }
        } else {
            log.warn "copyRemoteToLocal: Not interested in {}", item
        }
    }
}

private void copyItemToLocalRepo(ItemInfo item, String localRepoKey) {
    def localRepoPath = RepoPathFactory.create(localRepoKey, item.repoPath.path)
    if (!repositories.exists(localRepoPath)) {
        try {
            repositories.copy(item.repoPath, localRepoPath)
            log.warn "copyRemoteToLocal: Copied artifact '{}' to '{}'", item.repoPath, localRepoPath
        }
        catch (Exception e) {
            log.warn "copyRemoteToLocal: Unable to copy '{}' to '{}'. Exception: {}", item.repoPath, localRepoPath, e
        }
    } else {
        log.warn "copyRemoteToLocal: Local copy '{}' already exists", localRepoPath
    }
}
