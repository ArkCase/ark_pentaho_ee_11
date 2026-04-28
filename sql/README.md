# Pentaho Liquibase script adapters

The original Pentaho installation contains SQL scripts that both create users, databases, schemata, and other supporting structures prior to populating the schemata with the required tables.

This implies that some manual administrator intervention is required at the database level to prepare them to receive Pentaho data. The challenge here lies in the fact that this is impractical for containerized environments. Therefore, the decision was made to convert those SQL scripts - specifically those that could not be mimicked some other ways (more on that below) - into Liquibase XML changelogs to facilitate their conditional execution (using Liquibase), while also structuring them in such a way that it would be easy to either repeat the work in the future when a new version of Pentaho comes along that requires schematic changes, or to propagate those changes to the existing changelogs.

By doing things like this, we can use Liquibase's <sql> tags to basically wrap the entire schema population SQL in as close a syntax to the original SQL file as possible, while also retaining the ability to run it as a Liquibase changelog.o

## User creation

The only task that shouldn't be easily mimicked by these changelogs is the creation of the users, because this would require dissemination of the DB's administrator password. While this is possible, it's not very desirable.

Thus, we instead rely on other mechanisms we already have in play - namely: the database helm chart already contains the means to seed databases with a set of user accounts that can then be consumed by other containers/processes. Thus, this is the mechanism we rely on.

## Updating for a new Pentaho

This job is largely manual, since it requires several steps:

1. Compare the two Pentaho version's SQL scripts to identify differences that need propagating
1. Replicate those changes in these changelog XML files
1. Add/remove any whole SQL statements as required
1. Test the whole thing all over again

The good news is that this only needs to happen _*once*_ for each new version of Pentaho that will be supported. Thus, this is acceptable overhead of adoption.
