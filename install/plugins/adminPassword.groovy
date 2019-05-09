import groovy.transform.Field
import org.artifactory.api.context.ContextHelper
import org.artifactory.api.security.SecurityService
import org.artifactory.api.security.UserGroupService
import org.artifactory.factory.InfoFactoryHolder
import org.artifactory.security.UserInfo
import org.artifactory.security.props.auth.ApiKeyManager

changePassword()

void changePassword() {
    def passFile = new File('/artifactory_extra_conf/admin.password')
    log.info( "Updating admin password" )
    String password = passFile.text.trim()
    String userName = "admin"
    UserGroupService userGroupService = ContextHelper.get().beanForType(UserGroupService)
    SecurityService securityService = ContextHelper.get().beanForType(SecurityService)
    ApiKeyManager apiKeyManager = ContextHelper.get().beanForType(ApiKeyManager)
    UserInfo user = userGroupService.findOrCreateExternalAuthUser(userName, false)
    def saltedPassword = securityService.generateSaltedPassword(password)
    def newUser = InfoFactoryHolder.get().copyUser(user)
    newUser.setPassword(saltedPassword)
    userGroupService.updateUser(newUser, false)
    log.info( "Password updated for $newUser")
}
