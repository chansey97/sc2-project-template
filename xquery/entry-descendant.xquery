declare namespace map = "http://www.w3.org/2005/xpath-functions/map";
declare namespace file = "http://expath.org/ns/file";
declare namespace saxon = "http://saxon.sf.net/";
declare namespace prov = "java:ro.sync.exml.workspace.api.PluginWorkspaceProvider";
declare namespace work = "java:ro.sync.exml.workspace.api.PluginWorkspace";
declare namespace editorAccess = "java:ro.sync.exml.workspace.api.editor.WSEditor";
declare namespace editor-vars = "java:ro.sync.util.editorvars.EditorVariables";

let $current-node := saxon:evaluate(concat('doc(&quot;', base-uri(.), '&quot;)', path(.))),
$workspace := prov:getPluginWorkspace(),
    $editorAccess := work:getCurrentEditorAccess($workspace, 0),
    $pdu := editor-vars:expandEditorVariables('${pdu}',  $editorAccess),
    $configuration-doc := doc(concat($pdu, '/configuration.xml')),
    $model-doc := doc(concat($pdu, '/model.xml')),
    $class-by-name := map:merge(for $class in $model-doc/*/*/*:Class[not(starts-with(@name, 'S'))] return map:entry($class/@name, $class)),   
    $_class-hierarchy := function($class as element(), $visited as element()*, $f as function(*)) as element()*
    {
        let $superClass:= if($class/@superClass) then $class-by-name($class/@superClass) else ()
        return if($superClass and $superClass except $visited) then $f($superClass, ($visited, $superClass), $f)
                else $visited
    },
    $class-hierarchy := function($class as element()) as element()*
    {
        $_class-hierarchy($class, (), $_class-hierarchy)
    },
    $is-entry := function($node as node()) as xs:boolean
    {
        if($node/../name() = 'Catalog' and $node/name() ne 'const' and not(starts-with($node/name(), 'S'))) 
        then true()
        else false()
    },
    $resolve-parent-entry := function($entry as element()) as element()? 
    {
        let $current-doc-url := base-uri($entry),
            $current-doc := doc($current-doc-url),
            $current-mod := $configuration-doc/*/mod[starts-with(lower-case($current-doc-url), lower-case(@href))],
            $parent-mods := reverse($current-mod/preceding-sibling::*),
            $parent-catalog-urls := for $mod in $parent-mods
                                        return concat($mod/@href, 'Base.SC2Data/GameData/', file:name($current-doc-url)),
            $parent-catalog-docs := for $uri in $parent-catalog-urls
                                        return doc($uri),
            $current-visible-docs := ($current-doc, $parent-catalog-docs),
            $entry-id := function($entry as element()) as xs:string
            {
                if($entry/@id) then $entry/@id
                else $entry/name()
            },
            $find-entry-in-docs := function($id as xs:string, $docs as document-node()*) as element()?
            {
                (for $doc in $docs return $doc/*/*[$is-entry(.) and $entry-id(.) eq $id][1])[1]
            },
            $resolve-entry-by-parent := function($parent-id as xs:string) as element()?
            {
                $find-entry-in-docs($parent-id, $current-visible-docs)
            },
            $resolve-entry-by-id := function($id as xs:string) as element()?
            {
                $find-entry-in-docs($id, $parent-catalog-docs)
            },
            $resolve-entry-by-name := function($name as xs:string) as element()?
            {
                $find-entry-in-docs($name, $parent-catalog-docs)
            },
            $resolve-super-entry-by-name := function($name as xs:string) as element()?
            {
                let $class := $class-by-name($name)
                return 
                    if($class) then (for $class-name in reverse($class-hierarchy($class)/@name) return $find-entry-in-docs($class-name, $current-visible-docs))[1]
                    else error((), concat($name, ' not in model.xml, this maybe caused by version mismatch between the model.xml and SC2. To fix the problem, use version matched model.xml or add this Class to model.xml manually'))
            }
        return if($entry/@parent) then $resolve-entry-by-parent($entry/@parent)
                else if($entry/@id) then 
                                    let $resolved :=$resolve-entry-by-id($entry/@id)
                                    return 
                                            if($resolved) then $resolved
                                            else 
                                                let $resolved := $resolve-entry-by-name($entry/name())
                                                return 
                                                    if($resolved) then $resolved
                                                    else $resolve-super-entry-by-name($entry/name())
                else 
                    let $resolved := $resolve-entry-by-name($entry/name())
                    return 
                            if($resolved) then $resolved
                            else $resolve-super-entry-by-name($entry/name())
    },
    $_entry-hierarchy := function($entry as element(), $visited as element()*, $f as function(*)) as element()*
    {
        let $parent-entry := $resolve-parent-entry($entry)
        return if($parent-entry and $parent-entry except $visited) then $f($parent-entry, ($visited, $parent-entry), $f)
                else $visited
    },
    $entry-hierarchy := function($entry as element()) as element()*
    {
        $_entry-hierarchy($entry, (), $_entry-hierarchy)
    },
    $descendant := function($entry as element()) as element()*
    {
        let $current-doc-url := base-uri($entry),
            $current-doc := doc($current-doc-url),
            $current-mod := $configuration-doc/*/mod[starts-with(lower-case($current-doc-url), lower-case(@href))],
            $extend-mods := $current-mod/following-sibling::*,
            $extend-catalog-urls := for $mod in $extend-mods
                                        return concat($mod/@href, 'Base.SC2Data/GameData/', file:name($current-doc-url)),
            $extend-catalog-docs := for $uri in $extend-catalog-urls[doc-available(.)]
                                    return doc($uri),
            $current-or-extend-catalog-docs := ($current-doc, $extend-catalog-docs)
       return $current-or-extend-catalog-docs/*/*[$is-entry(.)][some $e in $entry-hierarchy(.) satisfies $e is $entry]
    }
return if($is-entry($current-node)) then $descendant($current-node) else ()