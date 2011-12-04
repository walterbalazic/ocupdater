// Garbler plug-in for the OpenCollar Project (c), original by Joy Stipe
// Licensed under the GPLv3, with the additional requirement that these scripts remain "full perms" in Second Life.  See "OpenCollar License" for details.

//v3.601 by Joy Stipe 2010/07/28

//OpenCollar MESSAGE MAP
// messages for authenticating users
integer COMMAND_OWNER = 500;
integer COMMAND_SECOWNER = 501;
integer COMMAND_GROUP = 502;
integer COMMAND_WEARER = 503;
integer COMMAND_EVERYONE = 504;
integer COMMAND_OBJECT = 506; 
integer COMMAND_RLV_RELAY = 507;
integer COMMAND_SAFEWORD = 510;
integer COMMAND_BLACKLIST = 520;
integer COMMAND_WEARERLOCKEDOUT = 521;

integer POPUP_HELP = 1001;

// messages for storing and retrieving values from http db
integer HTTPDB_SAVE = 2000;//scripts send messages on this channel to have settings saved to httpdb
//str must be in form of "token=value"
integer HTTPDB_REQUEST = 2001;//when startup, scripts send requests for settings on this channel
integer HTTPDB_RESPONSE = 2002;//the httpdb script will send responses on this channel
integer HTTPDB_DELETE = 2003;//delete token from DB
integer HTTPDB_EMPTY = 2004;//sent by httpdb script when a token has no value in the db

// same as HTTPDB_*, but for storing settings locally in the settings script
integer LOCALSETTING_SAVE = 2500;
integer LOCALSETTING_REQUEST = 2501;
integer LOCALSETTING_RESPONSE = 2502;
integer LOCALSETTING_DELETE = 2503;
integer LOCALSETTING_EMPTY = 2504;


// messages for creating OC menu structure
integer MENUNAME_REQUEST = 3000;
integer MENUNAME_RESPONSE = 3001;
integer MENUNAME_REMOVE = 3003;

// messages for RLV commands
integer RLV_CMD = 6000;
integer RLV_REFRESH = 6001;//RLV plugins should reinstate their restrictions upon receiving this message.
integer RLV_CLEAR = 6002;//RLV plugins should clear their restriction lists upon receiving this message.
integer RLV_VERSION = 6003; //RLV Plugins can recieve the used rl viewer version upon receiving this message..


string g_sParentMenu = "AddOns";
string GARBLE = "Garble On";
string UNGARBLE = "Garble Off";
integer g_nDebugMode=FALSE; // set to TRUE to enable Debug messages


string SAFE = "safeword"; // we'll replace this from httdb on resets
key gkWear;
string gsWear;
string gsFir;
integer giCRC;
integer giGL;
integer bOn;

Debug(string _m)
{
    if (!g_nDebugMode) return;
    llOwnerSay(llGetScriptName() + ": " + _m);
}

Notify(key _k, string _m, integer NotifyWearer)
{
    if (_k == gkWear) llOwnerSay(_m);
    else
    {
        if (llGetAgentSize(_k) != ZERO_VECTOR) llInstantMessage(_k, _m);
        if (NotifyWearer) llOwnerSay(_m);
    }
}

string GetDBPrefix()
{
    return llList2String(llParseString2List(llGetObjectDesc(), ["~"], []), 2);
}

string garble(string _i)
{
    // return punctuations unharmed
    if (_i == "." || _i == "," || _i == ";" || _i == ":" || _i == "?") return _i;
    if (_i == "!" || _i == " " || _i == "(" || _i == ")") return _i;
    // phonetically garble letters that have a rather consistent sound through a gag
    if (_i == "a" || _i == "e" || _i == "i" || _i == "o" || _i == "u" || _i == "y") return "eh";
    if (_i == "c" || _i == "k" || _i == "q") return "k";
    if (_i == "m") return "w";
    if (_i == "s" || _i == "z") return "shh";
    if (_i == "b" || _i == "p" || _i == "v") return "f";
    if (_i == "x") return "ek";
    // randomly garble everything else
    if (llFloor(llFrand(10.0) < 1)) return _i;
    return "nh";
}

bind(key _k)
{
    bOn = TRUE;
    llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + UNGARBLE, NULL_KEY);
    llMessageLinked(LINK_SET, MENUNAME_REMOVE, g_sParentMenu + "|" + GARBLE, NULL_KEY);
    llMessageLinked(LINK_SET, LOCALSETTING_SAVE, "garble=on", NULL_KEY);
    // Garbler only listen to the wearer, as a failsafe
    giGL = llListen(giCRC, "", gkWear, "");
    llMessageLinked(LINK_SET, RLV_CMD, "redirchat:" + (string)giCRC + "=add,chatshout=n,sendim=n", NULL_KEY);
    if (llGetAgentSize(_k) != ZERO_VECTOR)
    {
        if (_k != gkWear) llOwnerSay(llKey2Name(_k) + " ordered you to be quiet");
        Notify(_k, gsWear + "'s speech is now garbled", FALSE);
    }
}

release(key _k)
{
    bOn = FALSE;
    llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + GARBLE, NULL_KEY);
    llMessageLinked(LINK_SET, MENUNAME_REMOVE, g_sParentMenu + "|" + UNGARBLE, NULL_KEY);
    llMessageLinked(LINK_SET, LOCALSETTING_SAVE, "garble=off", NULL_KEY);
    llListenRemove(giGL);
    llMessageLinked(LINK_SET, RLV_CMD, "chatshout=y,sendim=y,redirchat:" + (string)giCRC + "=rem", NULL_KEY);
    if (llGetAgentSize(_k) != ZERO_VECTOR)
    {
        if (_k != gkWear) llOwnerSay("You are free to speak again");
        Notify(_k, gsWear + " is allowed to talk again", FALSE);
    }
}

default
{
    on_rez(integer _r)
    {
        if (llGetOwner() != gkWear) llResetScript();
    }
    state_entry()
    {
        gkWear = llGetOwner();
        gsWear = llKey2Name(gkWear);
        giCRC = llRound(llFrand(499) + 1);
        if (bOn) release(gkWear);
        llSleep(1.0);
    }
    listen(integer _c, string _n, key _k, string _m)
    {
        if (_c == giCRC)
        {
            if (_m == SAFE) // Wearer used the safeword
            {
                //if garbler is on, we have to inform the collar without garbling it
                llMessageLinked(LINK_THIS, COMMAND_OWNER, SAFE, gkWear);
                return;
            }
            string sOut;
            integer iL;
            integer iR;
            for (iL = 0; iL < llStringLength(_m); ++iL)
                sOut += garble(llToLower(llGetSubString(_m, iL, iL)));
            string sMe = llGetObjectName();
            llSetObjectName(gsWear);
            llWhisper(0, "/me mumbles: " + sOut);
            llSetObjectName(sMe);
            return;
        }
    }
    link_message(integer iL, integer iM, string sM, key kM)
    {
        if (iM >= COMMAND_OWNER && iM <= COMMAND_WEARER)
        {
            // menu calls
            integer nReshowMenu = FALSE;
            if (sM == "menu " + GARBLE)
            {
                nReshowMenu = TRUE;
                sM = GARBLE;
            }
            else if (sM == "menu " + UNGARBLE)
            {
                nReshowMenu = TRUE;
                sM = UNGARBLE;
            }
            // standard chat commands
            if (sM == "settings")
            {
                if (bOn) Notify(kM, "Garbled.", FALSE);
                else Notify(kM, "Not Garbled.", FALSE);
            }
            else if (sM == "reset")
            {
                if (iM == COMMAND_WEARER || iM == COMMAND_OWNER)
                    llResetScript();
            }
            else if (llToLower(sM) == llToLower(GARBLE) || llToLower(sM) == llToLower(UNGARBLE))
            {
                if (iM <= COMMAND_SECOWNER)
                {
                    if (llToLower(sM) == llToLower(GARBLE) && !bOn) bind(kM);
                    else if (llToLower(sM) == llToLower(UNGARBLE) && bOn) release(kM);
                }
                else Notify(kM, "Sorry, only Primary & Secondary Owners are allowed to toggle the Garbler feature.", FALSE);
            }
            if (nReshowMenu)
            {
                nReshowMenu = FALSE;
                llMessageLinked(LINK_SET, iM, "menu " + g_sParentMenu, kM);
            }
        }
        else if (iM == MENUNAME_REQUEST && sM == g_sParentMenu)
        {
            if (bOn) llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + UNGARBLE, NULL_KEY);
            else llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + GARBLE, NULL_KEY);
        }
        else if (iM == RLV_REFRESH)
        {
            if (bOn) llMessageLinked(LINK_SET, RLV_CMD, "redirchat:" + (string)giCRC + "=add,chatshout=n,sendim=n", NULL_KEY);
            else llMessageLinked(LINK_SET, RLV_CMD, "chatshout=y,sendim=y,redirchat:" + (string)giCRC + "=rem", NULL_KEY);
        }
        else if (iM == RLV_CLEAR)
        {
            release(kM);
        }
        else if (iM == HTTPDB_RESPONSE) // stored local cache is dumped initially as httpdbresponse @ login
        {
            list lP = llParseString2List(sM, ["="], []);
            string sT = llList2String(lP, 0);
            string sV = llList2String(lP, 1);
            if (sT == "garble")
            {
                if (sV == "on" && !bOn) bind(kM);
                else if (sV == "off" && bOn) release(kM);
            }
            else if (sT == "safeword") SAFE = sV;
        }
        else if (iM == HTTPDB_SAVE) // Have to update the safeword if it is changed between resets
        {
            integer iS = llSubStringIndex(sM, "=");
            if (llGetSubString(sM, 0, iS - 1) == "safeword")
                SAFE = llGetSubString(sM, iS + 1, -1);
        }
        else if (iM == COMMAND_EVERYONE)
        {
            //
        }
        else if (iM == COMMAND_SAFEWORD)
        {
            release(kM);
        }
    }
}