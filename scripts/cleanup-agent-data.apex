// Removes the cases one seed run created (same tag substitution as seed-agent-data.apex).
// Only cases with this run's tag AND created by the running user are deleted.
String runTag = '__RUN_TAG__';
if (runTag.startsWith('__')) { runTag = 'local'; }
String likePrefix = ('AGENT-SEED ' + runTag + ' ').replace('%', '\\%').replace('_', '\\_') + '%';
List<Case> rows = [SELECT Id FROM Case WHERE Subject LIKE :likePrefix AND CreatedById = :UserInfo.getUserId()];
delete rows;
System.debug(LoggingLevel.ERROR, 'CLEANED ' + rows.size() + ' cases for tag ' + runTag);
