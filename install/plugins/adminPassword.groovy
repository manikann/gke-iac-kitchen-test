import org.artifactory.api.context.ContextHelper
import org.artifactory.api.security.SecurityService
import org.artifactory.api.security.UserGroupService
import org.artifactory.factory.InfoFactoryHolder
import org.artifactory.security.UserInfo

changePassword()

void changePassword() {
    def passFile = new File('/artifactory_extra_conf/admin.password')
    if (passFile.exists() && passFile.canRead()) {
        log.info("Updating admin password")
        String password = passFile.text.trim()
        String userName = "admin"
        UserGroupService userGroupService = ContextHelper.get().beanForType(UserGroupService)
        SecurityService securityService = ContextHelper.get().beanForType(SecurityService)
        UserInfo user = userGroupService.findUser(userName)
        def saltedPassword = securityService.generateSaltedPassword(password)
        def newUser = InfoFactoryHolder.get().copyUser(user)
        newUser.setPassword(saltedPassword)
        userGroupService.updateUser(newUser, false)
        log.info("Password updated for $newUser")
    } else {
        log.warn("Password file not found")
    }
}
