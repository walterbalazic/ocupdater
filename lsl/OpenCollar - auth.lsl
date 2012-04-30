//OpenCollar - auth
//Licensed under the GPLv2, with the additional requirement that these scripts remain "full perms" in Second Life.  See "OpenCollar License" for details.

key g_kWearer;
list g_lAvatars; //strided list in form key,name,auth_num
key g_kGroup = "";
string g_sGroupName;
integer g_iGroupEnabled = 0;
string g_sAvatarBeingEdited; //used temporarily to store new owner or secowner name while retrieving key
key g_kAvatarBeingEdited;

string  g_sWikiURL = "http://code.google.com/p/opencollar/wiki/UserDocumentation";
string g_sParentMenu = "Main";
string g_sSubMenu = "Access";

key g_kHTTPID;
key g_kGroupHTTPID;

string g_sAvatarsToken = "avatars";

string g_sPrefix;

//dialog handlers
key g_kAuthMenuID;
key g_kKnownPeopleMenuID;
key g_kRegionPeopleMenuID;
key g_kEditMenuID;

//added for attachment auth
integer g_iInterfaceChannel = -12587429;

//MESSAGE MAP

// authed/authable commands
// 512..527, completed auth: from highest autority to lowest.
// Scripts should safely assume that every value within the interval has such purpose.
// Scripts should preferably use inequalities when checking autority level, as new levels might be inserted in the future,
// so that they can be handled consistently despite not knowing them yet.
integer LM_AUTHED_PRIMARY = 514;   // primary owner auth, can do close to anything (except what requires wearer's explicit consent)
integer LM_AUTHED_SECONDARY = 516; // secondary owner auth, same as primary but cannot change ownership/access options
integer LM_AUTHED_GUEST = 518;     // user is allowed to use collar basic and "harmless" commands but cannot "lock" anything
integer LM_AUTHED_DENIED = 526;     // user is denied access to the collar. Commands carried by such link messages should usually not be executed.
// 528..543, pending auth: the command carried by such a link message should not be acted upon until an auth plugin completes authentication.
// We assume that the value can only increase as a LM goes through several chained auth plugins (as to avoid loops), until it reach a completed auth state.
integer LM_TOAUTH_NEW = 532;     // before going through auth system
integer LM_TOAUTH_ASKWEARER = 534;       // maybe will not be use in a IM (theoretically). Placeholder for cases where the wearer should be asked directly.
integer LM_TOAUTH_PLUGIN = 536;    // auth is delegated to plugin, no further action should happen until an auth plugin increases the level

integer LM_DO_SAFEWORD = 599;
//added for attachment auth (garvin)
integer ATTACHMENT_REQUEST = 600;
integer ATTACHMENT_RESPONSE = 601;

integer POPUP_HELP = 1001;

integer LM_SETTING_SAVE = 2000;//scripts send messages on this channel to have settings saved to httpdb
//str must be in form of "token=value"
integer LM_SETTING_REQUEST = 2001;//when startup, scripts send requests for settings on this channel
integer LM_SETTING_RESPONSE = 2002;//the httpdb script will send responses on this channel
integer LM_SETTING_DELETE = 2003;//delete token from DB
integer LM_SETTING_EMPTY = 2004;//sent by httpdb script when a token has no value in the db

integer MENUNAME_REQUEST = 3000;
integer MENUNAME_RESPONSE = 3001;
integer MENUNAME_REMOVE = 3003;

integer RLV_CMD = 6000;
integer RLV_REFRESH = 6001;//RLV plugins should reinstate their restrictions upon receiving this message.
integer RLV_CLEAR = 6002;//RLV plugins should clear their restriction lists upon receiving this message.

integer ANIM_START = 7000;//send this with the name of an anim in the string part of the message to play the anim
integer ANIM_STOP = 7001;//send this with the name of an anim in the string part of the message to stop the anim

integer DIALOG = -9000;
integer DIALOG_RESPONSE = -9001;
integer DIALOG_TIMEOUT = -9002;

//this can change
integer WEARERLOCKOUT=620;

//EXTERNAL MESSAGE MAP
integer EXT_COMMAND_COLLAR = 499;

string UPMENU = "^";

string g_sAddAvatar = "Add Person";
string g_sEditAvatar = "Edit Person";
string g_sSetGroup = "Set Group";
string g_sReset = "Reset All";
string g_sListOwners = "List Rules";
string g_sPublicAccess = "Public Access";
string g_sGroupAccess = "Group Access";
string g_sSetLimitRange = "Limit Range";
string g_sUnsetLimitRange = "Unlimit Range";

integer g_iPublicAccess; // take an auth value
integer g_iGroupAccess; // take an auth value
integer g_iLimitRange=1; // 0: disabled, 1: limited
integer g_iWearerlocksOut;

integer g_iRemenu = FALSE;

key g_kDialoger;//the person using the dialog.  needed in the sensor event when scanning for new owners to add
integer g_iDialogerAuth; //auth of the person using the dialog

string getFullName(key kID)
{
    string sDName = llGetDisplayName(kID);
    string sLName = llKey2Name(kID);
    string sUName = llGetUsername(kID);
    if (llToLower(sDName) == llToLower(sLName) || llToLower(sDName) == llToLower(sUName)) return sDName;
    return sDName + " (" + sUName + ")";
}
string Num2AuthClassName(integer n)
{
    if (n == LM_TOAUTH_NEW) return "none";
    else if (n == LM_AUTHED_PRIMARY) return "primary owner";
    else if (n == LM_AUTHED_SECONDARY) return "secondary owner";
    else if (n == LM_AUTHED_GUEST) return "guest user";
    else if (n == LM_TOAUTH_ASKWEARER) return "ask wearer";
    else if (n == LM_TOAUTH_PLUGIN) return "plugin managed";
    else if (n == LM_AUTHED_DENIED) return "denied";
    else return "unknown";
}

integer AuthClassName2Num(string s)
{
    s = llToLower(s);
    if ((integer)s) return (integer) s;
    else if (s == "primary" || s == "owner" || s == "master" || s == "mistress") return LM_AUTHED_PRIMARY;
    else if (s == "secondary" || s == "secowner" || s == "operator") return LM_AUTHED_SECONDARY;
    else if (s == "sub" || s == "slave" || s == "guest" || s == "1" || s == "on" || s == "enabled" || s == "") return LM_AUTHED_GUEST;
    else if (s == "ask" || s == "ask wearer") return LM_TOAUTH_ASKWEARER;
    else if (s == "plugin" || s == "delegate") return LM_TOAUTH_PLUGIN;
    else if (s == "remove" || s == "0" || s == "off" || s == "disabled") return LM_TOAUTH_PLUGIN;  // handle that (group of) person as strangers... boils down to removing them
    else if (s == "block" || s == "blocked" || s == "blacklist" || s == "denied" || s == "lockout") return LM_AUTHED_DENIED;
    else return LM_TOAUTH_PLUGIN; // class name not understood, should be handled as an error
}


Debug(string sStr)
{
    //llOwnerSay(llGetScriptName() + ": " + sStr);
}

Notify(key kID, string sMsg, integer iAlsoNotifyWearer) {
    if (kID == g_kWearer) {
        llOwnerSay(sMsg);
    } else {
            llRegionSayTo(kID, 0, sMsg);
        if (iAlsoNotifyWearer) {
            llOwnerSay(sMsg);
        }
    }
}

sendToAttachmentInterface(string sMsg)
{
    llWhisper(g_iInterfaceChannel, "CollarCommand|" + (string) EXT_COMMAND_COLLAR + "|" + sMsg);
}

ChangePerson(key kID, string sName, integer iAuth, key kUser)
{//adds new/removes or edit existing owner, secowner, or blacklisted, as determined by type.
    integer iIndex = llListFindList(g_lAvatars, [(string)kID]);
    if (iAuth == LM_TOAUTH_PLUGIN)
    { //removing entry
        if (iIndex == -1)
        {
            Notify(kUser, "This avatar is currently not registered in the collar. Nothing changed.", FALSE);
        }
        else
        {
            integer iRemAuth = llList2Integer(g_lAvatars, iIndex + 2);
            string sRemType = Num2AuthClassName(iRemAuth);
            if (iRemAuth <= LM_AUTHED_GUEST)
            {
                if (kID != g_kWearer)
                // if it isnt the wearer, we are nice and notify them
                {
                    Notify(kID,"You have been removed as " + sRemType +" on " + getFullName(g_kWearer) + "'s collar.", FALSE);
                }
                else 
                {
                    Notify(kID, "You have been removed as " + sRemType +" on your own collar.", FALSE);
                }
            }
            g_lAvatars = llDeleteSubList(g_lAvatars, iIndex, iIndex + 2);
        }
    }
    else
    {
        string sType = Num2AuthClassName(iAuth);
        if (iIndex == -1)
        {   //owner is not already in list.  add him/her
            g_lAvatars += [(string)kID, sName, iAuth];
            Notify(g_kWearer, "Registered new avatar " + sName + " as " + sType + ".", FALSE);
        }
        else
        {   //owner is already in list.  just replace the name and auth level
            g_lAvatars = llListReplaceList(g_lAvatars, [sName, iAuth], iIndex + 1, iIndex + 2);
            Notify(g_kWearer, "Avatar " + sName + " is now " + sType + ".", FALSE);
        }
        if (kID != g_kWearer)
        {
            if (iAuth == LM_AUTHED_PRIMARY)
            {
                Notify(g_kWearer, "Your owner can have a lot of power over you and you consent to that by making them your owner on your collar. They can leash you, put you in poses, lock your collar, see your location and what you say in local chat.  If you are using RLV they can  undress you, make you wear clothes, restrict your  chat, IMs and TPs as well as force TP you anywhere they like. Please read the help for more info. If you do not consent, you can use the command \"" + g_sPrefix + "runaway\" to remove all owners from the collar.", FALSE);
            }
        }
        if (iAuth <= LM_AUTHED_GUEST) Notify(kID, "You have been registered as " + sType + " on " + getFullName(g_kWearer) + "'s collar.\nFor help concerning the collar usage either say \"" + g_sPrefix + "help\" in chat or go to " + g_sWikiURL + " .",FALSE);
    }

    if (llGetListLength(g_lAvatars) > 0)
    {
        llMessageLinked(LINK_SET, LM_SETTING_SAVE, g_sAvatarsToken + "=" + llDumpList2String(g_lAvatars, ","), "");
    }
    else
    {
        llMessageLinked(LINK_SET, LM_SETTING_DELETE, g_sAvatarsToken, "");
    }
    Notify(kUser, sName + "'s credential is now " + Num2AuthClassName(Auth(kID, FALSE)) + ".", TRUE);
    sendToAttachmentInterface("OwnerChange");
}

key Dialog(key kRCPT, string sPrompt, list lChoices, list lUtilityButtons, integer iPage, integer iAuth)
{
    //key generation
    //just pick 8 random hex digits and pad the rest with 0.  Good enough for dialog uniqueness.
    string sOut;
    integer n;
    for (n = 0; n < 8; ++n)
    {
        integer iIndex = (integer)llFrand(16);//yes this is correct; an integer cast rounds towards 0.  See the llFrand wiki entry.
        sOut += llGetSubString( "0123456789abcdef", iIndex, iIndex);
    }
    key kID = (sOut + "-0000-0000-0000-000000000000");
    llMessageLinked(LINK_SET, DIALOG, (string)kRCPT + "|" + sPrompt + "|" + (string)iPage + "|" 
        + llDumpList2String(lChoices, "`") + "|" + llDumpList2String(lUtilityButtons, "`") + "|" + (string)iAuth, kID);
    return kID;
} 

Name2Key(string sName)
{   //obtain formatted name from either username or legacy name, formatted name is firstname+lastname
    list lSeparated = llParseStringKeepNulls(sName, [" ","."], []);
    string sFormattedName;
    if (llGetListLength(lSeparated)==1) // new usernames
    {
        g_sAvatarBeingEdited = sName;
        sFormattedName = sName+"+resident";
    }
    else if (llGetListLength(lSeparated)==2) // old usernames or legacy names
    {
        g_sAvatarBeingEdited = llDumpList2String(lSeparated, ".");
        sFormattedName = llDumpList2String(lSeparated, "+");
    }
    else
    {
        Notify(g_kDialoger, "Avatar not found.", FALSE);
        return;
    }
    g_kHTTPID = llHTTPRequest("http://w-hat.com/name2key?terse=1&name=" + sFormattedName, [HTTP_METHOD, "GET"], "");
}

key RegionSearch(string name)
{
    name = llToLower(name);
    list lAgents = llGetAgentList(AGENT_LIST_REGION, []); // on OpenSim: osGetAgents()
    integer n = llGetListLength(lAgents);
    while (n--)
    {
        key kID = llList2Key(lAgents, n);
        string sDName = llToLower(llGetDisplayName(kID));
        string sLName = llToLower(llKey2Name(kID));
        string sUName = llToLower(llGetUsername(kID));
        if (sDName == name || sLName == name || sUName == name) return kID;
    }
    return NULL_KEY;
}

AuthMenu(key kAv, integer iAuth)
{
    string sPrompt = "Pick an option.";
    list lButtons = [g_sAddAvatar, g_sEditAvatar, g_sGroupAccess, g_sPublicAccess];

    if (g_iLimitRange) lButtons += [g_sUnsetLimitRange];    //set ranged
    else lButtons += [g_sSetLimitRange];    //unset open ranged

    lButtons += [g_sReset];

    //list owners
    lButtons += [g_sListOwners];

    g_kAuthMenuID = Dialog(kAv, sPrompt, lButtons, [UPMENU], 0, iAuth);
}

KnownPeopleMenu(key kID, integer iAuth)
{
    string sPrompt = "Choose the person to modify.";
    list lButtons;
    integer iNum= llGetListLength(g_lAvatars);
    integer n;
    for (n=1; n <= iNum/3; ++n)
    {
        string sName = llList2String(g_lAvatars, 3*n-2);
        if (sName != "")
        {
            lButtons += [sName];
        }
    }
    list lUtility;
//    if (g_iRemenu)
        lUtility = [UPMENU];
    g_kKnownPeopleMenuID = Dialog(kID, sPrompt, lButtons, lUtility, 0, iAuth);
}

EditItemMenu(string sName, key kID, integer iAuth)
{
    string sPrompt = "Pick a status for "+ sName + ".";
    list lButtons = ["Remove", "Primary", "Secondary", "Guest"];
    if (g_sAvatarBeingEdited != "_group" && g_sAvatarBeingEdited != "_public") lButtons += ["Block"];
    else lButtons += ["Ask wearer"];
    list lUtility;
//    if (g_iRemenu) 
        lUtility = [UPMENU];
    g_kEditMenuID = Dialog(kID, sPrompt, lButtons, lUtility, 0, iAuth);
}

RegionPeopleMenu(key kID, integer iAuth)
{
    list lButtons = llGetAgentList(AGENT_LIST_REGION, []);  // on OpenSim: osGetAgents()
    string sText;
    if (llGetListLength(lButtons) > 0)
    {
        sText = "Select who you would like to add or edit.";
    }
    else 
    {
        sText = "Nobody is in the region for the moment, maybe try later or in some other place?";
    }
    g_kRegionPeopleMenuID = Dialog(kID, sText, lButtons, [UPMENU], 0, iAuth);
}

integer in_range(key kID) {
    if (g_iLimitRange) {
        integer range = 20;
        vector kAvpos = llList2Vector(llGetObjectDetails(kID, [OBJECT_POS]), 0);
        if (llVecDist(llGetPos(), kAvpos) > range) {
            llDialog(kID, "\n\nNot in range...", [], 298479);
            return FALSE;
        }
        else return TRUE;
    }
    else return TRUE;
}

integer Auth(string kObjID, integer attachment)
{
    string kID = (string)llGetOwnerKey(kObjID); // if kObjID is an avatar key, then kID is the same key
    integer iNum; integer iIndex;
    if (g_iWearerlocksOut && kID == (string)g_kWearer && !attachment)
    {
        iNum = LM_AUTHED_DENIED;
    }
    else if (~(iIndex=llListFindList(g_lAvatars, [(string)kID])))
    {
        iNum = llList2Integer(g_lAvatars, iIndex + 2);
    }
    else if (kID == (string)g_kWearer)
    {
        if (llGetListLength(g_lAvatars) == 0) iNum = LM_AUTHED_PRIMARY;
        else iNum = LM_AUTHED_GUEST;
        //if no owners set, then wearer's cmds have owner auth
    }
    else if (g_iGroupEnabled && (string)llGetObjectDetails((key)kObjID, [OBJECT_GROUP]) == (string)g_kGroup && (key)kID != g_kWearer)
    {//meaning that the command came from an object set to our control group, and is not owned by the wearer
        iNum = g_iGroupAccess;
    }
    else if (llSameGroup(kID) && g_iGroupEnabled && kID != (string)g_kWearer)
    {
        if (in_range((key)kID)) iNum = g_iGroupAccess;
        else iNum = LM_AUTHED_DENIED;

    }
    else
    {
        if (in_range((key)kID)) iNum = g_iPublicAccess;
        else iNum = LM_AUTHED_DENIED;
    }
    return iNum;
}

integer isKey(string sIn) {
    if ((key)sIn) return TRUE;
    return FALSE;
}

integer OwnerCheck(key kID, integer iNum)
{//checks whether id has owner auth.  returns TRUE if so, else notifies person that they don't have that power
    //used in menu processing for when a non owner clicks an owner-only button
    if (iNum <= LM_AUTHED_PRIMARY) return TRUE;
    else
    {
        Notify(kID, "Sorry, only an owner can do that.", FALSE);
        return FALSE;
    }
}

NotifyAvatars(integer iNum, string sMsg)
{
    integer i;
    integer l=llGetListLength(g_lAvatars);
    key k;
    for (i = 0; i < l; i = i +3)
    {
        k = (key)llList2String(g_lAvatars,i);
        if (k != g_kWearer && llList2Integer(g_lAvatars, i+2) == iNum)
        {
            Notify(k, sMsg, FALSE);
        }
    }
}

// returns TRUE if eligible (AUTHED link message number)
integer UserCommand(integer iNum, string sStr, key kID) // here iNum: auth value, sStr: user command, kID: avatar id
{
    if (iNum == LM_AUTHED_DENIED) return TRUE;  // No command for people with no privilege in this plugin.
    else if (iNum > LM_AUTHED_DENIED || iNum < LM_AUTHED_PRIMARY) return FALSE; // sanity check
    list lParams = llParseString2List(sStr, [" "], []);
    string sCommand = llList2String(lParams, 0);
    if (sStr == "menu "+g_sSubMenu || sStr == "access" || sStr == "owners")
    {
        AuthMenu(kID, iNum);
    }
    else if (sCommand == "as")
    {
        integer iWanted = AuthClassName2Num(llList2String(lParams, 1));
        if (iWanted >= iNum && iWanted <= LM_AUTHED_DENIED)
        {
            sStr = llDumpList2String(llDeleteSubList(lParams, 0, 1), " ");
            Notify(kID, "Sending command \"" +sStr+ "\" as " + Num2AuthClassName(iWanted)+".", FALSE);
            llMessageLinked(LINK_SET, iWanted, sStr, kID);
        }
        else if (iWanted >= LM_AUTHED_PRIMARY && iWanted <= LM_AUTHED_DENIED)
             Notify(kID, "As " + Num2AuthClassName(iNum) + ", you do not have sufficient credentials for sending commands as " + Num2AuthClassName(iWanted)+".", FALSE);
        else Notify(kID, "Unrecognized auth level.", FALSE);
        return TRUE;
    }
    else if (sStr == "settings" || sStr == "listowners")
    {   //say owner, secowners, group
        if (iNum <= LM_AUTHED_PRIMARY || kID == g_kWearer)
        {
            //Do known avatars list
            integer n;
            integer iLength = llGetListLength(g_lAvatars);
            string sAvatars;
            for (n = 0; n < iLength; n = n + 3)
            {
                sAvatars += "\n" + llList2String(g_lAvatars, n + 1) + " (" + llList2String(g_lAvatars, n) + "): " + Num2AuthClassName(llList2Integer(g_lAvatars, n+2));
            }
            Notify(kID, "Known avatars: " + sAvatars,FALSE);

            Notify(kID, "Group: " + g_sGroupName,FALSE);
            Notify(kID, "Group Key: " + (string)g_kGroup,FALSE);
            string sVal = Num2AuthClassName(g_iGroupAccess);
            Notify(kID, "Goup Access: "+ sVal,FALSE);
            sVal = Num2AuthClassName(g_iPublicAccess);
            Notify(kID, "Public Access: "+ sVal,FALSE);
            string sValr; if (g_iLimitRange) sValr="true"; else sValr="false";
            Notify(kID, "LimitRange: "+ sValr,FALSE);
        }
        else if (sStr == "listowners")
        {
            Notify(kID, "Sorry, you are not allowed to see the owner list.",FALSE);
        }
    }
    else if (OwnerCheck(kID, iNum))
    { //respond to messages to set or unset owner, group, or secowners.  only owner may do these things
        if (sCommand == "add")
        { //set a new owner.  use w-hat sName2key service.  benefits: not case sensitive, and owner need not be present
            //if no owner at all specified:
            if (llGetListLength(lParams) == 1)
            {
                RegionPeopleMenu(kID, iNum);
                return TRUE;
            }
            string sName = llDeleteSubString(sStr, 0, 3);
            key kNew;
            if (isKey(sName)) kNew = (key)sName; 
            else kNew = RegionSearch(sName);
            if (kNew)
            {
                g_sAvatarBeingEdited = llGetUsername(kNew);
                g_kAvatarBeingEdited = kNew;
                EditItemMenu(g_sAvatarBeingEdited, kID, iNum);
            }
            else Name2Key(sName);
        }
        else if (sStr == "remove all")
        {
            string sSubName = llGetUsername(g_kWearer);
            NotifyAvatars(LM_AUTHED_PRIMARY, "You have been removed as " + Num2AuthClassName(LM_AUTHED_PRIMARY) + " on the collar of " + sSubName + ".");
            g_lAvatars = [];
            llMessageLinked(LINK_SET, LM_SETTING_DELETE, g_sAvatarsToken, "");
            Notify(kID, "Everybody was removed from the list of known people!",TRUE);
        }
        else if (sCommand == "edit")
        { //edit (or remove) avatar from the list of known people
            if (llGetListLength(lParams) == 1)
            {
                KnownPeopleMenu(kID, iNum);
            }
            else
            {
                string sName = llDeleteSubString(sStr, 0, 4);
                key kNew;
                if (isKey(sName)) kNew = (key)sName; 
                else
                {
                    integer iIndex = llListFindList(g_lAvatars, [llToLower(sName)]);
                    if (iIndex > 0) kNew = llList2Key(g_lAvatars, iIndex - 1);
                }
                if (kNew)
                {
                    g_sAvatarBeingEdited = sName;
                    g_kAvatarBeingEdited = kNew;
                    EditItemMenu(sName, kID, iNum);
                }
                else
                {
                    Notify(kID, "Avatar not found. Pick one from the list of registered avatars.", FALSE);
                    KnownPeopleMenu(kID, iNum);
                }
            }
        }
        else if (sCommand == "setgroup")
        {
            //if no arguments given, use current group, else use key provided
            if (isKey(llList2String(lParams, 1)))
            {
                g_kGroup = (key)llList2String(lParams, 1);
            }
            else
            {
                //record current group key
                g_kGroup = (key)llList2String(llGetObjectDetails(llGetKey(), [OBJECT_GROUP]), 0);
            }

            if (g_kGroup != "")
            {
                llMessageLinked(LINK_SET, LM_SETTING_SAVE, "group=" + (string)g_kGroup, "");
                g_iGroupEnabled = TRUE;
                g_kDialoger = kID;
                g_iDialogerAuth = iNum;
                //get group name from
                g_kGroupHTTPID = llHTTPRequest("http://world.secondlife.com/group/" + (string)g_kGroup, [], "");
            }
//            if(g_iRemenu)
//            {
//                g_iRemenu = FALSE;
                AuthMenu(kID, iNum);
//            }
        }
        else if (sCommand == "groupaccess")
        {
            if (llGetListLength(lParams) >= 2)
            {
                g_iGroupAccess = AuthClassName2Num(llList2String(lParams, 1));
                Notify(kID, "Group access set to "+ Num2AuthClassName(g_iGroupAccess)+".", FALSE);
                if (g_iGroupAccess != LM_TOAUTH_PLUGIN)
                {
                    llMessageLinked(LINK_SET, LM_SETTING_SAVE, "groupaccess=" + (string) g_iGroupAccess, "");
                }
                else
                {
                    llMessageLinked(LINK_SET, LM_SETTING_DELETE, "groupaccess", "");
                }
                sendToAttachmentInterface("OwnerChange");
            }
            else 
            {
                g_sAvatarBeingEdited = "_group";
                EditItemMenu("members of group "+g_sGroupName, kID, iNum);
            }
        }
        else if (sCommand == "publicaccess")
        {
            if (llGetListLength(lParams) >= 2)
            {
                g_iPublicAccess = AuthClassName2Num(llList2String(lParams, 1));
                Notify(kID, "Open access set to "+ Num2AuthClassName(g_iPublicAccess)+".", FALSE);
                if (g_iPublicAccess != LM_TOAUTH_PLUGIN)
                {
                    llMessageLinked(LINK_SET, LM_SETTING_SAVE, "publicaccess=" + (string) g_iPublicAccess, "");
                }
                else
                {
                    llMessageLinked(LINK_SET, LM_SETTING_DELETE, "publicaccess", "");
                    Notify(kID, "Public access disabled.", FALSE);
                }
                sendToAttachmentInterface("OwnerChange");
            }
            else 
            {
                g_sAvatarBeingEdited = "_public";
                EditItemMenu("public access", kID, iNum);
            }
        }
        else if (sCommand == "setlimitrange")
        {
            g_iLimitRange = TRUE;
            // as the default is range limit on, we do not need to store anything for this
            llMessageLinked(LINK_SET, LM_SETTING_DELETE, "limitrange", "");
            Notify(kID, "Range limited set.", FALSE);
            if(g_iRemenu)
            {
                g_iRemenu = FALSE;
                AuthMenu(kID, iNum);
            }
        }
        else if (sCommand == "unsetlimitrange")
        {
            g_iLimitRange = FALSE;
            // save off state for limited range (default is on)
            llMessageLinked(LINK_SET, LM_SETTING_SAVE, "limitrange=" + (string) g_iLimitRange, "");
            Notify(kID, "Range limited unset.", FALSE);
            if(g_iRemenu)
            {
                g_iRemenu = FALSE;
                AuthMenu(kID, iNum);
            }
        }
        else if (sCommand == "reset")
        {
            llResetScript();
        }
    }
    return TRUE;
}

default
{
    state_entry()
    {   //until set otherwise, wearer is owner
        Debug((string)llGetFreeMemory());
        g_kWearer = llGetOwner();
        list sName = llParseString2List(llKey2Name(g_kWearer), [" "], []);
        g_sPrefix = llToLower(llGetSubString(llList2String(sName, 0), 0, 0)) + llToLower(llGetSubString(llList2String(sName, 1), 0, 0));
        //added for attachment auth
        g_iInterfaceChannel = (integer)("0x" + llGetSubString(g_kWearer,30,-1));
        if (g_iInterfaceChannel > 0) g_iInterfaceChannel = -g_iInterfaceChannel;
        
        
        // hardcoded defaults:
        g_iPublicAccess = LM_TOAUTH_PLUGIN;
        g_iGroupAccess = LM_TOAUTH_PLUGIN;
        
        // Request owner list.  Be careful about doing this in all scripts,
        // because we can easily flood the 64 event limit in LSL's event queue
        // if all the scripts send a ton of link messages at the same time on
        // startup.
        llMessageLinked(LINK_SET, LM_SETTING_REQUEST, g_sAvatarsToken, "");
    }

    link_message(integer iSender, integer iNum, string sStr, key kID)
    {  //authenticate messages on LM_TOAUTH_NEW
        if (iNum == LM_TOAUTH_NEW)
        {
            integer iAuth = Auth((string)kID, FALSE);
            if ((kID == g_kWearer) && (sStr=="reset" || sStr=="runaway"))
            {   // note that this will work *even* if the wearer is blacklisted or locked out
                // otherwise forbid anybody who is not the wearer or primary owner
                Notify(g_kWearer, "Running away from all owners started, your owners will now be notified!",FALSE);
                integer n;
                integer stop = llGetListLength(g_lAvatars);
                for (n = 0; n < stop; n += 3)
                {
                    key kOwner = (key)llList2String(g_lAvatars, n);
                    if (kOwner != g_kWearer && llList2Integer(g_lAvatars, n+2) == LM_AUTHED_PRIMARY)
                    {
                        Notify(kOwner, llKey2Name(g_kWearer) + " has run away!",FALSE);
                    }
                }
                Notify(g_kWearer, "Runaway finished, the collar will now reset!",FALSE);
                llMessageLinked(LINK_SET, LM_AUTHED_PRIMARY, "runaway", kID); // handled by settings script
                return;
            }
            else
            {
                llMessageLinked(LINK_SET, iAuth, sStr, kID);
            }

            Debug("noauth: " + sStr + " from " + (string)kID + " who has auth " + (string)iAuth);
        }
        else if (UserCommand(iNum, sStr, kID)) return;
        else if (iNum == LM_SETTING_RESPONSE)
        {
            list lParams = llParseString2List(sStr, ["="], []);
            string sToken = llList2String(lParams, 0);
            string sValue = llList2String(lParams, 1);
            if (sToken == g_sAvatarsToken)
            {
                // temporarily stash owner list so we can see if it's changing.
                list tmpavatars = g_lAvatars;
                g_lAvatars = llParseString2List(sValue, [","], []);

                // only say the owner list if it has changed.  This includes on
                // rez, since we reset (and therefore blank the owner list) on
                // rez.
                if (llGetListLength(g_lAvatars) && tmpavatars != g_lAvatars) {
                    // SA, TODO: here, list owners to llOwnerSay
                }
            }
            else if (sToken == "group")
            {
                g_kGroup = (key)sValue;
                //check to see if the object's group is set properly
                if (g_kGroup != "")
                {
                    if ((key)llList2String(llGetObjectDetails(llGetKey(), [OBJECT_GROUP]), 0) == g_kGroup)
                    {
                        g_iGroupEnabled = TRUE;
                    }
                    else
                    {
                        g_iGroupEnabled = FALSE;
                    }
                }
                else
                {
                    g_iGroupEnabled = FALSE;
                }
            }
            else if (sToken == "groupname")
            {
                g_sGroupName = sValue;
            }
            else if (sToken == "groupaccess")
            {
                g_iGroupAccess = (integer)sValue;
            }
            else if (sToken == "publicaccess")
            {
                g_iPublicAccess = (integer)sValue;
            }
            else if (sToken == "limitrange")
            {
                g_iLimitRange = (integer)sValue;
            }
            else if (sToken == "prefix")
            {
                g_sPrefix = sValue;
            }
        }
        else if (iNum == MENUNAME_REQUEST && sStr == g_sParentMenu)
        {
            llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + g_sSubMenu, "");
        }
        else if (iNum == LM_DO_SAFEWORD)
        {
            string sSubName = llKey2Name(g_kWearer);
            string sSubFirstName = llList2String(llParseString2List(sSubName, [" "], []), 0);
            NotifyAvatars(LM_AUTHED_PRIMARY, "Your sub " + sSubName + " has used the safeword. Please check on " + sSubFirstName +"'s well-being and if further care is required.");
            //added for attachment interface (Garvin)
        sendToAttachmentInterface("safeword");
        }
        //added for attachment auth (Garvin)
        else if (iNum == ATTACHMENT_REQUEST)
        {
            integer iAuth = Auth((string)kID, TRUE);
            llMessageLinked(LINK_SET, ATTACHMENT_RESPONSE, (string)iAuth, kID);
        }
        else if (iNum == WEARERLOCKOUT)
        {
            if (sStr == "on")
            {
                g_iWearerlocksOut=TRUE;
                Debug("locksOuton");
            }
            else if (sStr == "off")
            {
                g_iWearerlocksOut=FALSE;
                Debug("lockoutoff");
            }
        }
        else if (iNum == DIALOG_RESPONSE)
        {
            if (llListFindList([g_kAuthMenuID, g_kKnownPeopleMenuID, g_kRegionPeopleMenuID, g_kEditMenuID], [kID]) != -1)
            {
                list lMenuParams = llParseString2List(sStr, ["|"], []);
                key kAv = (key)llList2String(lMenuParams, 0);
                string sMessage = llList2String(lMenuParams, 1);
                integer iPage = (integer)llList2String(lMenuParams, 2);
                integer iAuth = (integer)llList2String(lMenuParams, 3);
                if (kID == g_kAuthMenuID)
                {
                    //g_kAuthMenuID responds to setowner, setsecowner, setblacklist, remowner, remsecowner, remblacklist
                    //setgroup, unsetgroup, setopenaccess, unsetopenaccess
                    if (sMessage == UPMENU)
                    {
                        llMessageLinked(LINK_SET, iAuth, "menu " + g_sParentMenu, kAv);
                        return;
                    }
                    else if (sMessage == g_sAddAvatar)
                        UserCommand(iAuth, "add", kAv);
                    else if (sMessage == g_sEditAvatar)
                        UserCommand(iAuth, "edit", kAv);    
                    else if (sMessage == g_sGroupAccess)
                        UserCommand(iAuth, "groupaccess", kAv);
                    else if (sMessage == g_sPublicAccess)
                        UserCommand(iAuth, "publicaccess", kAv);
                    else if (sMessage == g_sSetGroup)
                        {UserCommand(iAuth, "setgroup", kAv); AuthMenu(kAv, iAuth);}
                    else if (sMessage == g_sSetLimitRange)
                        {UserCommand(iAuth, "setlimitrange", kAv); AuthMenu(kAv, iAuth);}
                    else if (sMessage == g_sUnsetLimitRange)
                        {UserCommand(iAuth, "unsetlimitrange", kAv); AuthMenu(kAv, iAuth);}
                    else if (sMessage == g_sListOwners)
                    {
                        UserCommand(iAuth, "listowners", kAv);
                        AuthMenu(kAv, iAuth);
                    }
                    else if (sMessage == g_sReset)
                    { // separate routine
                        llMessageLinked(LINK_SET, LM_TOAUTH_NEW, "runaway", kAv);
                    }
                }
                else if (kID == g_kRegionPeopleMenuID)
                {
                    if (sMessage == UPMENU) AuthMenu(kAv, iAuth);
                    else UserCommand(iAuth, "add " + sMessage, kAv);
                }
                else if (kID == g_kKnownPeopleMenuID)
                {
                    if (sMessage == UPMENU) AuthMenu(kAv, iAuth);
                    else if (sMessage)
                    {
//                        g_iRemenu = TRUE;
                        UserCommand(iAuth, "edit " + sMessage, kAv);
                    }
                }
                else if (kID == g_kEditMenuID)
                {
                    if (sMessage != UPMENU)
                    { 
                        integer iNewAuth = AuthClassName2Num(sMessage);
                        if (g_sAvatarBeingEdited == "_public") UserCommand(iAuth, "publicaccess "+(string)iNewAuth, kAv);
                        else if (g_sAvatarBeingEdited == "_group") UserCommand(iAuth, "groupaccess "+(string)iNewAuth, kAv);
                        else ChangePerson(g_kAvatarBeingEdited, llGetUsername(g_kAvatarBeingEdited), iNewAuth, kAv);
                    }
//                    if (g_iRemenu) {g_iRemenu = FALSE; 
                    AuthMenu(kAv, iAuth);
//                    }
                }
            }

        }
    }

    on_rez(integer iParam)
    {
        llResetScript();
    }

    changed(integer iChange)
    {
        if (iChange & CHANGED_OWNER)
        {
            llResetScript();
        }
    }

    http_response(key kID, integer iStatus, list lMeta, string sBody)
    {
        if (kID == g_kHTTPID)
        {   //here's where we add owners or secowners, after getting their keys
            if (iStatus == 200)
            {
                Debug(sBody);
                if (isKey(sBody))
                {
                    g_kAvatarBeingEdited = (key)sBody;
                    EditItemMenu(g_kAvatarBeingEdited, g_kDialoger, g_iDialogerAuth);
                }
                else
                {
                    Notify(g_kDialoger, "Error: unable to retrieve key for '" + g_sAvatarBeingEdited + "'.", FALSE);
                }
            }
        }
        else if (kID == g_kGroupHTTPID)
        {
            g_sGroupName = "X";
            if (iStatus == 200)
            {
                integer iPos = llSubStringIndex(sBody, "<title>");
                integer iPos2 = llSubStringIndex(sBody, "</title>");
                if ((~iPos) // Found
                    && iPos2 > iPos // Has to be after it
                    && iPos2 <= iPos + 43 // 36 characters max (that's 7+36 because <title> has 7)
                    && !~llSubStringIndex(sBody, "AccessDenied") // Check as per groupname.py (?)
                   )
                {
                    g_sGroupName = llGetSubString(sBody, iPos + 7, iPos2 - 1);
                }
            }

            if (g_sGroupName == "X")
            {
                Notify(g_kDialoger, "Group set to (group name hidden).", FALSE);
            }
            else
            {
                Notify(g_kDialoger, "Group set to " + g_sGroupName, FALSE);
            }
            llMessageLinked(LINK_SET, LM_SETTING_SAVE, "groupname=" + g_sGroupName, "");
        }
    }
}