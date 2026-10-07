//+------------------------------------------------------------------+
//| NABICHA BIG GAME V1 |
//+------------------------------------------------------------------+
#property copyright "NABICHA - Kinshasa"
#property version "1.0"
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

//===================== PANNEAU UTILISATEUR =========================
input string ___________TRADES___________ = "--- CONFIG 3 TRADES INDEPENDANTS ---";
input bool Activer_Trade1 = true;
input double Lot_Trade1 = 0.04;
input int TP_Trade1_Pips = 150; // 150 pips = 15$ sur 0.01 lot Gold
input bool Activer_Trade2 = true;
input double Lot_Trade2 = 0.03;
input int TP_Trade2_Pips = 350; // 350 pips = 35$
input bool Activer_Trade3 = false;
input double Lot_Trade3 = 0.01;
input int TP_Trade3_Pips = 800; // 800 pips = 80$ de base
input int Trailing_Trade3_Pips = 400; // Trailing 40$ pour laisser filer à 120$+

input string ___________SL_BE___________ = "--- SL COMMUN ET BE ---";
input int SL_Pips = 100;
input int BE_Pips = 50;
input int BE_Offset_Pips = 10; // BE + 1$ pour frais

input string ___________FILTRES___________ = "--- FILTRES GROS MOUVEMENT ---";
input int EMA_Fast_H1 = 50;
input int EMA_Slow_H1 = 200;
input int EMA_M5_Pullback = 21;
input int RSI_Periode = 14;
input int ADX_Periode = 14;
input int ADX_Min = 25;
input int BOS_Lookback_M15 = 20;
input double Max_Distance_EMA_M5_Pips = 180;

input string ___________NEWS_5_SLOTS___________ = "--- FILTRE NEWS 5 SLOTS KINSHASA ---";
input bool ActiverFiltreNews = true;
input int PauseAvantNews_Min = 15;
input int PauseApresNews_Min = 15;
input bool News1_Active=true; input string News1_Nom="CPI USD"; input int News1_H=22; input int News1_M=15;
input bool News2_Active=true; input string News2_Nom="FOMC"; input int News2_H=22; input int News2_M=30;
input bool News3_Active=true; input string News3_Nom="NFP USD"; input int News3_H=23; input int News3_M=15;
input bool News4_Active=false; input string News4_Nom="PPI USD"; input int News4_H=23; input int News4_M=30;
input bool News5_Active=false; input string News5_Nom="Retail Sales"; input int News5_H=0; input int News5_M=15;

input string ___________SECURITE___________ = "--- SECURITE ET NOTIFICATIONS ---";
input double MaxSpreadPoints = 500;
input bool ActiverPush = true;
input bool Notif_Ouverture = true;
input bool Notif_TP = true;
input bool Notif_SL = true;
input bool Notif_BE = true;
input bool Notif_Heartbeat = true;
input int IntervalleHeartbeat_Min = 60;
input bool Notif_Rapport22h = true;
input int HeureRapportKin = 22;
input bool Notif_News = true;
input bool Notif_Spread = true;

//===================== VARIABLES GLOBALES =========================
int hEMA50_H1, hEMA200_H1, hADX_M15, hRSI_M5, hEMA21_M5;
datetime dernierHeartbeat, derniereAlerteSpread, derniereHeureRapport;
double soldeDebutJour;
string derniereTendanceH1="";
bool enPauseNews=false;
string newsActuelle="";

//===================== INIT =========================
int OnInit(){
   hEMA50_H1 = iMA(_Symbol,PERIOD_H1,EMA_Fast_H1,0,MODE_EMA,PRICE_CLOSE);
   hEMA200_H1 = iMA(_Symbol,PERIOD_H1,EMA_Slow_H1,0,MODE_EMA,PRICE_CLOSE);
   hADX_M15 = iADX(_Symbol,PERIOD_M15,ADX_Periode);
   hRSI_M5 = iRSI(_Symbol,PERIOD_M5,RSI_Periode,PRICE_CLOSE);
   hEMA21_M5 = iMA(_Symbol,PERIOD_M5,EMA_M5_Pullback,0,MODE_EMA,PRICE_CLOSE);
   dernierHeartbeat = TimeGMT();
   derniereHeureRapport = TimeGMT();
   soldeDebutJour = AccountInfoDouble(ACCOUNT_BALANCE);
   PrintFormat("NABICHA BIG BOT demarre sur %s (%s). Push: %s.",_Symbol,EnumToString(_Period),ActiverPush?"active":"desactive");
   if(ActiverPush){
      ResetLastError();
      if(!SendNotification(StringFormat("NABICHA demarre sur %s (%s). Bot actif.",_Symbol,EnumToString(_Period)))){
         PrintFormat("Echec notification de demarrage. Erreur MT5: %d",GetLastError());
      }
   }
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){
   string texteRaison = "";
   
   if(reason==0) texteRaison = "Le bot s'est arrêté tout seul (ExpertRemove)";
   if(reason==1) texteRaison = "TU as enlevé le bot à la main du graphique";
   if(reason==2) texteRaison = "TU as recompilé dans MetaEditor";
   if(reason==3) texteRaison = "TU as changé de timeframe ou de symbole (ex: M5 -> M15)";
   if(reason==4) texteRaison = "TU as fermé le graphique";
   if(reason==5) texteRaison = "TU as changé un paramètre dans le panneau (Lot, TP, SL)";
   if(reason==6) texteRaison = "TU as changé de compte trading";
   if(reason==7) texteRaison = "TU as changé de chart ou le marché est fermé";
   if(reason==8) texteRaison = "Template changé";
   if(reason==9) texteRaison = "TU as fermé MT5";

   if(ActiverPush){
      SendNotification(StringFormat("🔴 NABICHA BIG BOT ARRETE\n\nRaison claire: %s\n\nCode technique: raison %d\nHeure Kin: %02d:%02d\n\nSi c'est toi qui a fait l'action, c'est normal. Remets le bot.",texteRaison,reason,tmHourKin(),tmMinKin()));
   }
   
   Print("=== NABICHA ARRET ===");
   Print("Raison claire: ",texteRaison);
   Print("Code: raison ",reason);
}

//===================== TICK PRINCIPAL =========================
void OnTick(){
   // HEARTBEAT 60 MIN
   if(Notif_Heartbeat && TimeGMT()-dernierHeartbeat >= IntervalleHeartbeat_Min*60){
      EnvoyerHeartbeatComplet(); dernierHeartbeat=TimeGMT();
   }
   // RAPPORT 22H KINSHASA
   VerifierRapport22hComplet();
   // GERER LES POSITIONS AVANT LES FILTRES QUI SUSPENDENT LES NOUVELLES ENTREES
   if(PositionsTotal()>0) GererToutesPositions();
   // FILTRE NEWS
   if(VerifierPauseNewsDetail()) return;
   // FILTRE SPREAD
   double spread = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   if(spread > MaxSpreadPoints){
      if(Notif_Spread && TimeGMT()-derniereAlerteSpread > 1800){
         SendNotification(StringFormat("⚠️ SPREAD ELEVE - BIG BOT EN PAUSE\nSpread actuel: %.1f points (%.1f pips)\nMax autorise: %.1f points\nHeure Kin: %02d:%02d\nBot attend spread normal.",spread,spread/10.0,MaxSpreadPoints,tmHourKin(),tmMinKin()));
         derniereAlerteSpread=TimeGMT();
      } return;
   } else {
      if(derniereAlerteSpread!=0 && spread < MaxSpreadPoints*0.7){
         SendNotification(StringFormat("🟢 SPREAD NORMALISE\nXAUUSD\nSpread: %.1f pips - BIG BOT chasse a nouveau.",spread/10.0));
         derniereAlerteSpread=0;
      }
   }
   // HORAIRE KINSHASA 07-20h
   MqlDateTime tm; TimeToStruct(TimeGMT(),tm); int hKin=tm.hour+1; if(hKin<7 || hKin>20) return;

   // PAS DE NOUVELLE ENTREE TANT QU'UNE POSITION EST OUVERTE
   if(PositionsTotal()>0) return;

   // RECHERCHE SETUP GROS MOUVEMENT
   double ema50[], ema200[]; CopyBuffer(hEMA50_H1,0,0,2,ema50); CopyBuffer(hEMA200_H1,0,0,2,ema200);
   bool tendanceHausse = ema50[0] > ema200[0]; bool tendanceBaisse = ema50[0] < ema200[0];
   if(!tendanceHausse &&!tendanceBaisse) return;

   double adx[], adxPlus[], adxMinus[]; CopyBuffer(hADX_M15,0,0,1,adx); CopyBuffer(hADX_M15,1,0,1,adxPlus); CopyBuffer(hADX_M15,2,0,1,adxMinus);
   if(adx[0] < ADX_Min) return;

   double highM15[], lowM15[], closeM15[]; CopyHigh(_Symbol,PERIOD_M15,0,BOS_Lookback_M15+1,highM15); CopyLow(_Symbol,PERIOD_M15,0,BOS_Lookback_M15+1,lowM15); CopyClose(_Symbol,PERIOD_M15,0,3,closeM15);
   ArraySetAsSeries(highM15,true); ArraySetAsSeries(lowM15,true); ArraySetAsSeries(closeM15,true);
   double plusHaut = highM15[1]; double plusBas = lowM15[1];
   for(int i=2;i<=BOS_Lookback_M15;i++){ if(highM15[i]>plusHaut) plusHaut=highM15[i]; if(lowM15[i]<plusBas) plusBas=lowM15[i]; }
   bool bosBuy = closeM15[0] > plusHaut; bool bosSell = closeM15[0] < plusBas;
   if(!bosBuy &&!bosSell) return;

   double rsi[], ema21[]; CopyBuffer(hRSI_M5,0,0,1,rsi); CopyBuffer(hEMA21_M5,0,0,1,ema21);
   double prixActuel = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double distEMA = MathAbs(prixActuel - ema21[0]) / _Point / 10.0;
   if(distEMA > Max_Distance_EMA_M5_Pips) return;
   if(rsi[0] < 40 || rsi[0] > 60) return;

   // ENTREE
   if(tendanceHausse && bosBuy && rsi[0]>=45 && rsi[0]<=60 && adxPlus[0]>adxMinus[0]) OuvrirLes3Trades(ORDER_TYPE_BUY, plusHaut, plusBas, adx[0]);
   if(tendanceBaisse && bosSell && rsi[0]>=40 && rsi[0]<=55 && adxMinus[0]>adxPlus[0]) OuvrirLes3Trades(ORDER_TYPE_SELL, plusHaut, plusBas, adx[0]);
}

//===================== OUVERTURE 3 TRADES =========================
void OuvrirLes3Trades(ENUM_ORDER_TYPE type, double hh, double ll, double adxVal){
   double prix = (type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = (type==ORDER_TYPE_BUY)?prix - SL_Pips*10*_Point : prix + SL_Pips*10*_Point;
   int nb=0;
   if(Activer_Trade1){ double tp=(type==ORDER_TYPE_BUY)?prix+TP_Trade1_Pips*10*_Point:prix-TP_Trade1_Pips*10*_Point; if(trade.PositionOpen(_Symbol,type,Lot_Trade1,prix,sl,tp,"NABICHA T1 "+IntegerToString(TP_Trade1_Pips)+"p")) nb++; }
   if(Activer_Trade2){ double tp=(type==ORDER_TYPE_BUY)?prix+TP_Trade2_Pips*10*_Point:prix-TP_Trade2_Pips*10*_Point; if(trade.PositionOpen(_Symbol,type,Lot_Trade2,prix,sl,tp,"NABICHA T2 "+IntegerToString(TP_Trade2_Pips)+"p")) nb++; }
   if(Activer_Trade3){ double tp=(type==ORDER_TYPE_BUY)?prix+TP_Trade3_Pips*10*_Point:prix-TP_Trade3_Pips*10*_Point; if(trade.PositionOpen(_Symbol,type,Lot_Trade3,prix,sl,tp,"NABICHA T3 "+IntegerToString(TP_Trade3_Pips)+"p TRAIL")) nb++; }
   if(Notif_Ouverture && nb>0 && ActiverPush){
      SendNotification(StringFormat("🦁 NABICHA BIG BOT - %s DETECTE - %d TRADE(S) OUVERT(S)\n\n📍 Prix Entree: %.2f\n🛑 SL COMMUN: %.2f (%d pips = %.2f$)\n\n🎯 T1: %.2f (%d pips = %.2f$)\n🎯 T2: %.2f (%d pips = %.2f$)\n🎯 T3: %.2f (%d pips = %.2f$) + trailing %d pips\n\n📊 Setup:\nTendance H1: %s\nBOS M15: %.2f casse\nADX: %.1f\nRSI M5: Pullback OK\nEMA21 M5: Distance OK\n\n⏰ Heure Kin: %02d:%02d\nOn vise GROS - RR 1:3 a 1:8",type==ORDER_TYPE_BUY?"ACHAT GEANT":"VENTE GEANTE",nb,prix,sl,SL_Pips,SL_Pips*0.1*Lot_Trade1/0.01,prix+(type==ORDER_TYPE_BUY?1:-1)*TP_Trade1_Pips*10*_Point,TP_Trade1_Pips,TP_Trade1_Pips*0.1*Lot_Trade1/0.01,prix+(type==ORDER_TYPE_BUY?1:-1)*TP_Trade2_Pips*10*_Point,TP_Trade2_Pips,TP_Trade2_Pips*0.1*Lot_Trade2/0.01,prix+(type==ORDER_TYPE_BUY?1:-1)*TP_Trade3_Pips*10*_Point,TP_Trade3_Pips,TP_Trade3_Pips*0.1*Lot_Trade3/0.01,Trailing_Trade3_Pips,tendanceHausseOuBaisse(),type==ORDER_TYPE_BUY?hh:ll,adxVal,tmHourKin(),tmMinKin()));
   }
}

//===================== GESTION POSITIONS =========================
void GererToutesPositions(){
   for(int i=0;i<PositionsTotal();i++){
      ulong ticket=PositionGetTicket(i); if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      double entree=PositionGetDouble(POSITION_PRICE_OPEN); double prix=PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl=PositionGetDouble(POSITION_SL); double tp=PositionGetDouble(POSITION_TP);
      string com=PositionGetString(POSITION_COMMENT); ENUM_POSITION_TYPE t=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double profitPips = (t==POSITION_TYPE_BUY)?(prix-entree)/_Point/10.0:(entree-prix)/_Point/10.0;
      // BE
      double nouveauBE = (t==POSITION_TYPE_BUY)?entree + BE_Offset_Pips*10*_Point : entree - BE_Offset_Pips*10*_Point;
      nouveauBE = NormaliserPrixSymbole(nouveauBE);
      bool ameliorerBE = (t==POSITION_TYPE_BUY)?(sl==0 || sl<nouveauBE):(sl==0 || sl>nouveauBE);
      if(profitPips >= BE_Pips && ameliorerBE){
         ResetLastError();
         bool modifie = trade.PositionModify(ticket,nouveauBE,tp);
         uint codeRetour = trade.ResultRetcode();
         if(modifie && codeRetour==TRADE_RETCODE_DONE){
            sl = nouveauBE;
            if(Notif_BE && ActiverPush) SendNotification(StringFormat("🛡️ NABICHA BE ACTIVE - %s\nEntree: %.2f\nNouveau SL: %.2f (BE + %d pips)\nProfit actuel: +%.1f pips\nOn ne peut plus perdre - On laisse courir vers TP gros!",com,entree,nouveauBE,BE_Offset_Pips,profitPips));
         } else if(!modifie || codeRetour!=TRADE_RETCODE_NO_CHANGES){
            PrintFormat("Echec modification SL au BE pour la position #%I64u: code %u (%s), erreur %d",ticket,codeRetour,trade.ResultRetcodeDescription(),GetLastError());
         }
      }
      // TRAILING T3 SEULEMENT
      if(StringFind(com,"T3")>=0 && profitPips > TP_Trade1_Pips*0.8){
         double nSL = (t==POSITION_TYPE_BUY)?prix - Trailing_Trade3_Pips*10*_Point : prix + Trailing_Trade3_Pips*10*_Point;
         nSL = NormaliserPrixSymbole(nSL);
         if((t==POSITION_TYPE_BUY && nSL > sl) || (t==POSITION_TYPE_SELL && (sl==0 || nSL < sl))){
            ResetLastError();
            bool modifie = trade.PositionModify(ticket,nSL,tp);
            uint codeRetour = trade.ResultRetcode();
            if(modifie && codeRetour==TRADE_RETCODE_DONE){
               sl = nSL;
            } else if(!modifie || codeRetour!=TRADE_RETCODE_NO_CHANGES){
               PrintFormat("Echec modification du trailing pour la position #%I64u: code %u (%s), erreur %d",ticket,codeRetour,trade.ResultRetcodeDescription(),GetLastError());
            }
         }
      }
   }
}

double NormaliserPrixSymbole(double prix){
   double tailleTick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tailleTick>0) prix=MathRound(prix/tailleTick)*tailleTick;
   return NormalizeDouble(prix,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
}

//===================== HEARTBEAT COMPLET 60 MIN =========================
void EnvoyerHeartbeatComplet(){
   double bal=AccountInfoDouble(ACCOUNT_BALANCE); double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double profitJour=eq-soldeDebutJour;
   double e50[], e200[]; CopyBuffer(hEMA50_H1,0,0,1,e50); CopyBuffer(hEMA200_H1,0,0,1,e200);
   double adx[]; CopyBuffer(hADX_M15,0,0,1,adx); double rsi[]; CopyBuffer(hRSI_M5,0,0,1,rsi);
   string tendance = (e50[0]>e200[0])?"🟢 HAUSSIERE H1 - Cherche ACHAT":"🔴 BAISSIERE H1 - Cherche VENTE";
   string adxEtat = (adx[0]>=ADX_Min)?"✅ ADX Fort - Pret a exploser":"⏳ ADX Faible - Marche mou, on attend";
   string msg=StringFormat("📡 NABICHA BIG BOT - ACTIF EN CHASSE - %02d:%02d KIN\n\n💰 Solde: $%.2f\n💵 Equity: $%.2f\n📈 Jour: %s$%.2f\n📍 Positions ouvertes: %d\n\n📊 ANALYSE EN TEMPS REEL:\n%s\n💪 ADX M15: %.1f - %s\n📉 RSI M5: %.1f\n\n🎯 CONFIG CHASSE:\nT1: %s %d pips Lot %.2f\nT2: %s %d pips Lot %.2f\nT3: %s %d pips + trailing %d Lot %.2f\nSL: %d pips commun\n\n🔍 Statut: En attente BOS M15 (%d bougies) + Pullback EMA%d M5\nBot vivant, tout va bien.\n\nNABICHA BIG GAME ULTIMATE",tmHourKin(),tmMinKin(),bal,eq,profitJour>=0?"+":"",profitJour,PositionsTotal(),tendance,adx[0],adxEtat,rsi[0],Activer_Trade1?"ON":"OFF",TP_Trade1_Pips,Lot_Trade1,Activer_Trade2?"ON":"OFF",TP_Trade2_Pips,Lot_Trade2,Activer_Trade3?"ON":"OFF",TP_Trade3_Pips,Trailing_Trade3_Pips,Lot_Trade3,SL_Pips,BOS_Lookback_M15,EMA_M5_Pullback);
   if(ActiverPush) SendNotification(msg);
}

//===================== RAPPORT 22H KINSHASA =========================
void VerifierRapport22hComplet(){
   if(!Notif_Rapport22h) return; MqlDateTime tm; TimeToStruct(TimeGMT(),tm); int hKin=tm.hour+1; int m=tm.min;
   if(hKin==HeureRapportKin && m>=0 && m<=5 && TimeGMT()-derniereHeureRapport > 3500){
      double bal=AccountInfoDouble(ACCOUNT_BALANCE); double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      double profitJour=eq-soldeDebutJour;
      string msg=StringFormat("📊 RAPPORT JOURNALIER 22H00 KINSHASA - NABICHA BIG BOT\n\n💰 Solde cloture: $%.2f\n💵 Equity: $%.2f\n📈 Resultat du jour: %s$%.2f\n📍 Positions encore ouvertes: %d\n\n🎯 Config du jour:\nT1 %d pips (%.2f$) - %s\nT2 %d pips (%.2f$) - %s\nT3 %d pips + trailing %d (%.2f$+) - %s\nSL: %d pips commun\n\nTendance fin de jour: %s\n\n💤 Bot passe en veille 22h-07h Kin\nReprise chasse demain 07h00\nBravo chasseur!\n\nNABICHA",bal,eq,profitJour>=0?"+":"",profitJour,PositionsTotal(),TP_Trade1_Pips,TP_Trade1_Pips*0.1,Activer_Trade1?"ON":"OFF",TP_Trade2_Pips,TP_Trade2_Pips*0.1,Activer_Trade2?"ON":"OFF",TP_Trade3_Pips,Trailing_Trade3_Pips,TP_Trade3_Pips*0.1,Activer_Trade3?"ON":"OFF",SL_Pips,derniereTendanceH1);
      if(ActiverPush) SendNotification(msg);
      derniereHeureRapport=TimeGMT(); soldeDebutJour=bal;
   }
}

//===================== NEWS DETAILLE =========================
bool VerifierPauseNewsDetail(){
   if(!ActiverFiltreNews) return false; MqlDateTime tm; TimeToStruct(TimeGMT(),tm); int now=(tm.hour+1)*60+tm.min;
   int hs[5]={News1_H,News2_H,News3_H,News4_H,News5_H}; int ms[5]={News1_M,News2_M,News3_M,News4_M,News5_M}; bool acts[5]={News1_Active,News2_Active,News3_Active,News4_Active,News5_Active}; string noms[5]={News1_Nom,News2_Nom,News3_Nom,News4_Nom,News5_Nom};
   for(int i=0;i<5;i++){ if(!acts[i]) continue; int newsT=hs[i]*60+ms[i]; int debut=newsT-PauseAvantNews_Min; int fin=newsT+PauseApresNews_Min;
      if(now>=debut && now<fin){ if(!enPauseNews){ enPauseNews=true; newsActuelle=noms[i]; if(Notif_News && ActiverPush) SendNotification(StringFormat("⚠️ PAUSE NEWS - %s - BIG BOT EN PAUSE\nNews prevue: %02d:%02d Kin\nPause: %02d:%02d a %02d:%02d Kin\nBot ne prend plus de trade, positions actuelles gardees avec SL.",noms[i],hs[i],ms[i],debut/60,debut%60,fin/60,fin%60)); } return true; }
   }
   if(enPauseNews){ enPauseNews=false; if(Notif_News && ActiverPush) SendNotification("🟢 FIN PAUSE NEWS - "+newsActuelle+"\nBIG BOT reprend la chasse - Recherche opportunites a nouveau."); newsActuelle=""; }
   return false;
}
string tendanceHausseOuBaisse(){ double e50[], e200[]; CopyBuffer(hEMA50_H1,0,0,1,e50); CopyBuffer(hEMA200_H1,0,0,1,e200); return(e50[0]>e200[0])?"HAUSSE H1":"BAISSE H1"; }
int tmHourKin(){ MqlDateTime tm; TimeToStruct(TimeGMT(),tm); return tm.hour+1; }
int tmMinKin(){ MqlDateTime tm; TimeToStruct(TimeGMT(),tm); return tm.min; }
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& req, const MqlTradeResult& res){
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD){ if(HistoryDealSelect(trans.deal)){ double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT); string com=HistoryDealGetString(trans.deal,DEAL_COMMENT); if(profit!=0 && ActiverPush){ if(profit>0 && Notif_TP) SendNotification(StringFormat("💰 BIG BOT TP TOUCHE - %s\nResultat: +$%.2f (%.1f pips)\n%s\nNABICHA",com,profit,profit*10,profit>=30?"🎉 GROS TRADE - BRAVO CHASSEUR!":"✅")); if(profit<0 && Notif_SL) SendNotification(StringFormat("🛑 BIG BOT SL TOUCHE - %s\nPerte: -$%.2f\nSL 100 pips respecte - Prochain setup en chasse\nNABICHA",com,MathAbs(profit))); } } }
}