//+------------------------------------------------------------------+
//| BOKWETE BOT V1.1 |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;
input double LotSize = 0.01;
input int SL_Points = 300;
input int TP_Points = 450;
input int EMA_Fast = 7;
input int EMA_Slow = 21;
input int ADX_Periode = 14;
input double ADX_Minimum = 22.0;
input double MaxSpreadPoints = 500;
input double PerteMaxJournaliere = 5.0;
input double ObjectifJournalier = 7.0;

//--- NEWS SÉPARÉES - INTACT
input bool ActiverFiltreNews = true;
input int PauseAvantNews_Min = 15;
input int PauseApresNews_Min = 15;
input bool News1_Active = true; input string News1_Nom = "CPI"; input int News1_Heure_Kin = 22; input int News1_Minute_Kin = 15;
input bool News2_Active = true; input string News2_Nom = "FOMC"; input int News2_Heure_Kin = 22; input int News2_Minute_Kin = 30;
input bool News3_Active = true; input string News3_Nom = "NFP"; input int News3_Heure_Kin = 23; input int News3_Minute_Kin = 15;
input bool News4_Active = false; input string News4_Nom = "PPI"; input int News4_Heure_Kin = 23; input int News4_Minute_Kin = 30;
input bool News5_Active = false; input string News5_Nom = "Retail"; input int News5_Heure_Kin = 0; input int News5_Minute_Kin = 15;

//--- NOUVEAU : FILTRE RSI - AJOUTÉ
input bool ActiverFiltreRSI = true;
input double RSI_Seuil_Achat = 50.0; // Achat seulement si RSI > 50
input double RSI_Seuil_Vente = 50.0; // Vente seulement si RSI < 50

//--- NOTIFS V1.3 INTACTES
input bool ActiverPush = true;
input bool Notif_Ouverture = true;
input bool Notif_TP = true;
input bool Notif_SL = true;
input bool Notif_BE = true;
input bool Notif_ChangementTendance = true;
input bool Notif_Spread = true;
input bool Notif_LimiteJournaliere = true;
input bool Notif_Erreur = true;
input bool Notif_Connexion = true;
input bool Notif_Heartbeat = true;
input int IntervalleHeartbeat = 60;
input bool Notif_RapportJournalier = true;
input int HeureRapportKin = 22;
input bool Notif_News = true;

int hFast, hSlow, hADX, hRSI, hEMA_M5;
double soldeDebutJour;
datetime dernierHeartbeat, dernierAlerteSpread, dernierAlerteTendance, dernierAlerteConnexion;
bool tradingBloque = false; bool enPauseNews = false; string newsEnCours = ""; string derniereTendance = "";

int OnInit(){ hFast=iMA(_Symbol,PERIOD_M1,EMA_Fast,0,MODE_EMA,PRICE_CLOSE); hSlow=iMA(_Symbol,PERIOD_M1,EMA_Slow,0,MODE_EMA,PRICE_CLOSE); hADX=iADX(_Symbol,PERIOD_M1,ADX_Periode); hRSI=iRSI(_Symbol,PERIOD_M1,14,PRICE_CLOSE); hEMA_M5=iMA(_Symbol,PERIOD_M5,50,0,MODE_EMA,PRICE_CLOSE); soldeDebutJour=AccountInfoDouble(ACCOUNT_BALANCE); dernierHeartbeat=TimeGMT(); if(ActiverPush) SendNotification("🟢 BOKWETE BOT SCALPER DEMARRE \nSolde: $"+DoubleToString(soldeDebutJour,2)); return(INIT_SUCCEEDED); }

void OnTick(){
   VerifierConnexion();
   if(VerifierPauseNews()) return;
   if(tradingBloque){ VerifierLimites(); return; }
   if(Notif_Heartbeat && TimeGMT()-dernierHeartbeat > IntervalleHeartbeat*60){ EnvoyerHeartbeat(); dernierHeartbeat=TimeGMT(); }
   VerifierRapportJournalier();
   double spread=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   if(spread > MaxSpreadPoints){ if(Notif_Spread && TimeGMT()-dernierAlerteSpread > 1800){ Notifier("⚠️ SPREAD ELEVE\nXAUUSD\nSpread actuel: "+DoubleToString(spread/10.0,2)+"\nMaximum autorise: "+DoubleToString(MaxSpreadPoints/10.0,2)+"\nEntrees suspendues."); dernierAlerteSpread=TimeGMT(); } return; } else if(dernierAlerteSpread!=0 && spread < MaxSpreadPoints*0.8){ Notifier("🟢 SPREAD NORMALISE\nXAUUSD\nSpread: "+DoubleToString(spread/10.0,2)+"\nTrading autorise a nouveau."); dernierAlerteSpread=0; }
   VerifierTendance(); VerifierLimites(); if(tradingBloque) return; if(PositionsTotal()>0){ VerifierBE(); return; }
   MqlDateTime tm; TimeToStruct(TimeGMT(),tm); int hKin=tm.hour+1; if(hKin<9 || hKin>18) return;
   double adx[]; CopyBuffer(hADX,0,0,1,adx); if(adx[0]<ADX_Minimum) return;
   
   //--- LECTURE RSI POUR FILTRE
   double rsi[]; CopyBuffer(hRSI,0,0,1,rsi);
   
   double f[],s[]; CopyBuffer(hFast,0,0,2,f); CopyBuffer(hSlow,0,0,2,s); ArraySetAsSeries(f,true); ArraySetAsSeries(s,true);
   
   //--- NOUVELLE CONFLUENCE RSI AJOUTÉE
   if(f[1] < s[1] && f[0] > s[0]){
      if(!ActiverFiltreRSI || rsi[0] > RSI_Seuil_Achat) OuvrirPosition(ORDER_TYPE_BUY);
   }
   if(f[1] > s[1] && f[0] < s[0]){
      if(!ActiverFiltreRSI || rsi[0] < RSI_Seuil_Vente) OuvrirPosition(ORDER_TYPE_SELL);
   }
}

bool VerifierPauseNews(){
   if(!ActiverFiltreNews) return false;
   int minuteActuelle = tmHourKin()*60 + tmMin();
   for(int n=1;n<=5;n++){ bool active=false; string nom=""; int h=0,m=0;
      if(n==1){ active=News1_Active; nom=News1_Nom; h=News1_Heure_Kin; m=News1_Minute_Kin; }
      if(n==2){ active=News2_Active; nom=News2_Nom; h=News2_Heure_Kin; m=News2_Minute_Kin; }
      if(n==3){ active=News3_Active; nom=News3_Nom; h=News3_Heure_Kin; m=News3_Minute_Kin; }
      if(n==4){ active=News4_Active; nom=News4_Nom; h=News4_Heure_Kin; m=News4_Minute_Kin; }
      if(n==5){ active=News5_Active; nom=News5_Nom; h=News5_Heure_Kin; m=News5_Minute_Kin; }
      if(!active) continue;
      int minuteNews=h*60+m; int debutPause=minuteNews-PauseAvantNews_Min; int finPause=minuteNews+PauseApresNews_Min;
      if(minuteActuelle>=debutPause && minuteActuelle<finPause){ if(!enPauseNews){ enPauseNews=true; newsEnCours=nom; if(Notif_News) Notifier(StringFormat("⚠️ PAUSE NEWS - %s\nXAUUSD\nNews prevue: %02d:%02d Kin\nDebut pause: %02d:%02d\nReprise prevue: %02d:%02d\nNouvelles entrees suspendues.",nom,h,m,debutPause/60,debutPause%60,finPause/60,finPause%60)); } return true; }
   }
   if(enPauseNews){ enPauseNews=false; if(Notif_News) Notifier("🟢 FIN PAUSE NEWS - "+newsEnCours+"\nXAUUSD\nTrading autorise a nouveau."); newsEnCours=""; }
   return false;
}

void OuvrirPosition(ENUM_ORDER_TYPE type){
   double prix=(type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl=(type==ORDER_TYPE_BUY)?prix-SL_Points*10*_Point:prix+SL_Points*10*_Point;
   double tp=(type==ORDER_TYPE_BUY)?prix+TP_Points*10*_Point:prix-TP_Points*10*_Point;
   double rsi[]; CopyBuffer(hRSI,0,0,1,rsi); string tendance=GetTendanceM5();
   if(!trade.PositionOpen(_Symbol,type,LotSize,prix,sl,tp)){ if(Notif_Erreur) Notifier("🚨 ERREUR BOKWETE GOLD SCALPER\nImpossible d'ouvrir "+(type==ORDER_TYPE_BUY?"ACHAT":"VENTE")+" XAUUSD\nCode MT5: "+IntegerToString(GetLastError())); return; }
   if(Notif_Ouverture){ string emoji=(type==ORDER_TYPE_BUY)?"🟢":"🔴"; string sens=(type==ORDER_TYPE_BUY)?"ACHAT":"VENTE"; Notifier(StringFormat("%s BOKWETE GOLD SCALPER\n%s XAUUSD\nEntree: %.2f\nLot: %.2f\nSL: %.2f\nTP: %.2f\nRR: 1:1.5\nRSI M1: %.0f\nTendance M5: %s\nHeure Kin: %02d:%02d",emoji,sens,prix,LotSize,sl,tp,rsi[0],tendance,tmHourKin(),tmMin())); }
}
void VerifierBE(){ for(int i=0;i<PositionsTotal();i++){ PositionGetTicket(i); if(PositionGetSymbol(i)!=_Symbol) continue; double entree=PositionGetDouble(POSITION_PRICE_OPEN); double prix=PositionGetDouble(POSITION_PRICE_CURRENT); double sl=PositionGetDouble(POSITION_SL); ENUM_POSITION_TYPE t=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE); double pts=(t==POSITION_TYPE_BUY)?(prix-entree)/_Point:(entree-prix)/_Point; if(pts>200 && ((t==POSITION_TYPE_BUY && sl<entree)||(t==POSITION_TYPE_SELL && sl>entree))){ trade.PositionModify(_Symbol,entree,PositionGetDouble(POSITION_TP)); if(Notif_BE) Notifier(StringFormat("🛡️ SEUIL DE RENTABILITE ACTIVE\nXAUUSD %s %.2f\nEntree: %.2f\nNouveau SL: %.2f\nTrade securise\nBOKWETE",t==POSITION_TYPE_BUY?"ACHAT":"VENTE",LotSize,entree,entree)); } } }
void VerifierLimites(){ double profit=AccountInfoDouble(ACCOUNT_EQUITY)-soldeDebutJour; if(profit<=-PerteMaxJournaliere && !tradingBloque && Notif_LimiteJournaliere){ tradingBloque=true; Notifier(StringFormat("🚨 LIMITE DE PERTE JOURNALIERE ATTEINTE\nXAUUSD\nResultat du jour: -$%.2f\nNouvelles entrees: BLOQUEES\nBOKWETE",MathAbs(profit))); } if(profit>=ObjectifJournalier && !tradingBloque){ tradingBloque=true; Notifier(StringFormat("🏆 OBJECTIF JOURNALIER ATTEINT\nResultat: +$%.2f\nNouvelles entrees: BLOQUEES\nBravo, coupe l'ecran !\nBOKWETE",profit)); } MqlDateTime tm; TimeToStruct(TimeGMT(),tm); if(tm.hour==0 && tm.min==0){ soldeDebutJour=AccountInfoDouble(ACCOUNT_BALANCE); tradingBloque=false; } }
string GetTendanceM5(){ double ema[]; CopyBuffer(hEMA_M5,0,0,1,ema); double p=SymbolInfoDouble(_Symbol,SYMBOL_BID); return(p>ema[0])?"🟢 HAUSSIERE":"🔴 BAISSIERE"; }
void VerifierTendance(){ string now=GetTendanceM5(); if(derniereTendance!="" && derniereTendance!=now && Notif_ChangementTendance && TimeGMT()-dernierAlerteTendance>900){ Notifier("🔄 CHANGEMENT DE TENDANCE\nXAUUSD\nM5: "+derniereTendance+" -> "+now+"\nLe bot cherche maintenant des "+(StringFind(now,"HAUSSIERE")>=0?"ACHATS":"VENTES")+"."); dernierAlerteTendance=TimeGMT(); } derniereTendance=now; }
void EnvoyerHeartbeat(){ string t=GetTendanceM5(); MqlDateTime tm; TimeToStruct(TimeGMT(),tm); int hKin=tm.hour+1; string sess=(hKin>=9&&hKin<13)?"Londres":"New York"; Notifier(StringFormat("📡 BOKWETE GOLD SCALPER - ACTIF\nXAUUSD\nSolde: $%.2f\nCapital: $%.2f\nPositions: %d\nStatut: Recherche d'opportunite\nSession: %s\nTendance M5: %s\nHeure Kin: %02d:%02d",AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY),PositionsTotal(),sess,t,tmHourKin(),tmMin())); }
void VerifierRapportJournalier(){ if(tmHourKin()==HeureRapportKin && tmMin()==0 && Notif_RapportJournalier){ double p=AccountInfoDouble(ACCOUNT_EQUITY)-soldeDebutJour; Notifier(StringFormat("📊 RAPPORT JOURNALIER - BOKWETE GOLD SCALPER\n💰 Solde: $%.2f\n💵 Capital: $%.2f\nResultat du jour: %s$%.2f\nXAUUSD\nBOKWETE",AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY),p>=0?"+":"",p)); } }
void VerifierConnexion(){ if(!TerminalInfoInteger(TERMINAL_CONNECTED) && Notif_Connexion && TimeGMT()-dernierAlerteConnexion>600){ Notifier("🔴 CONNEXION MT5 PERDUE\nBOKWETE GOLD SCALPER\nXAUUSD\nLe terminal ne communique plus correctement avec le serveur."); dernierAlerteConnexion=TimeGMT(); } if(TerminalInfoInteger(TERMINAL_CONNECTED) && dernierAlerteConnexion!=0){ Notifier("🟢 CONNEXION RETABLIE\nBOKWETE GOLD SCALPER\nTrading operationnel."); dernierAlerteConnexion=0; } }
int tmHourKin(){ MqlDateTime tm; TimeToStruct(TimeGMT(),tm); return tm.hour+1; }
int tmMin(){ MqlDateTime tm; TimeToStruct(TimeGMT(),tm); return tm.min; }
void Notifier(string msg){ if(ActiverPush) SendNotification(msg); }
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& req, const MqlTradeResult& res){ if(trans.type==TRADE_TRANSACTION_DEAL_ADD){ if(HistoryDealSelect(trans.deal)){ double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT); if(profit!=0){ if(profit>0 && Notif_TP) Notifier(StringFormat("🎯 OBJECTIF ATTEINT (TP)\nXAUUSD\nLot: %.2f\nResultat: +$%.2f\nRR: 1:1.5\nBOKWETE",trans.volume,profit)); if(profit<0 && Notif_SL) Notifier(StringFormat("🛑 STOP LOSS TOUCHE\nXAUUSD\nLot: %.2f\nResultat: -$%.2f\nProtection active\nBOKWETE",trans.volume,MathAbs(profit))); } } } }