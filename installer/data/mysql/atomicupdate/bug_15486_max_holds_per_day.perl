$DBversion = "XXX";
if ( CheckVersion($DBversion) ) {

    if ( !column_exists( 'issuingrules', 'max_holds_per_day' ) ) {
        $dbh->do(q{
            ALTER TABLE `issuingrules`
                ADD COLUMN `max_holds_per_day` SMALLINT(6) DEFAULT NULL
                AFTER `holds_per_record`
        });
    }

    print "Upgrade to $DBversion done (Bug 15486: Restrict number of holds placed by day)\n";
    SetVersion($DBversion);
}
