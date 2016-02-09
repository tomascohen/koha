<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:z="http://indexdata.com/zebra-2.0"
                xmlns:kohaidx="http://www.koha.org/schemas/index-defs"
                version="1.0">

    <!-- xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" -->


    <xsl:output indent="yes" method="xml" version="1.0" encoding="UTF-8"/>

    <xsl:variable name="spaces">
        <xsl:text>!"#$%&amp;'\()*+,-./:;&lt;=&gt;?@\[\\]^_`\{|}~</xsl:text>
    </xsl:variable>
    
    <xsl:variable name="lcletters">abcdefghijklmnopqrstuvwxyzñaeiouaeiouaeiouaeiouaeiouaeiou</xsl:variable>
    <xsl:variable name="ucletters">ABCDEFGHIJKLMNOPQRSTUVWXYZÑÁÉÍÓÚÀÈÌÒÙÄËÏÖÜáéíóúàèìòùäëïöü</xsl:variable>

    
    <!-- disable all default text node output -->
    <xsl:template match="text()"/>

    <xsl:template match="/INDICES">
        <INDICES>
        <xsl:apply-templates select="indice"/>
        </INDICES>
    </xsl:template>

    <xsl:template match="indice">
        <!--<xsl:variable name="mi_id1" select="lower-case(replace(normalize-space(text()), $spaces, ' '))"/>
        <xsl:variable name="mi_id1" select="translate(translate(normalize-space(text()), $spaces, ' '), $ucletters, $lcletters)"/>
        <xsl:variable name="mi_id2" select="normalize-space(@tipo)"/>-->
        <z:record type="update">
            <xsl:variable name="idField" select="@id"/>
            <xsl:attribute name="z:id">
                <!-- <xsl:value-of select="concat(translate($mi_id2, ' ', ''),'-',translate($mi_id1, ' ', ''),'-',generate-id())"/> -->
                <xsl:value-of select="$idField"/>
            </xsl:attribute>
            <z:index name="any:w indice:w indice:p indice:s">
                <xsl:value-of select="."/>
            </z:index>
            <z:index name="tipo:0">
                <xsl:value-of select="@tipo"/>
            </z:index>
            <z:index name="id:0">
                <xsl:value-of select="@id"/>
            </z:index>
            <xsl:apply-templates/>
        </z:record>
    </xsl:template>

</xsl:stylesheet>
