$DBversion = 'XXX';
if( CheckVersion( $DBversion ) ) {

    unless ( TableExists('marc_merge_rules') ) {
        $dbh->do(q{
            CREATE TABLE `marc_merge_rules` (
                `id`          INT(11)     NOT NULL AUTO_INCREMENT, -- Merge rule ID
                `name`        VARCHAR(24) NOT NULL,                -- Merge rule name
                `description` VARCHAR(255),                        -- Merge rule description
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        });
    }
    unless ( TableExists('marc_merge_tag_rules') ) {
        $dbh->do(q{
            CREATE TABLE `marc_merge_tag_rules` (
                `id`          INT(11)      NOT NULL AUTO_INCREMENT, -- Tag merge rule ID
                `tag_filter`  VARCHAR(255) NOT NULL,                -- Tag number or regexp to be applied for matching the record tags
                `action`      ENUM('skip','overwrite','append') NOT NULL DEFAULT 'skip', -- Action on tags matching tag_filter
                `overwrite_indicators` TINYINT(1) DEFAULT 0, -- If action is overwrite, if indicators should be overwritten
                `marc_merge_rule_id` INT(11), -- Id of the merge rule the individual rule belongs to
                PRIMARY KEY (`id`),
                CONSTRAINT `marc_merge_tag_rules_ibfk1` FOREIGN KEY (`marc_merge_rule_id`) REFERENCES `marc_merge_rules` (`id`) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        });
    }

    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug 14957 - MARC overlay field policy)\n";
}
