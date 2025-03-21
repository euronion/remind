*** |  (C) 2006-2023 Potsdam Institute for Climate Impact Research (PIK)
*** |  authors, and contributors see CITATION.cff file. This file is part
*** |  of REMIND and licensed under AGPL-3.0-or-later. Under Section 7 of
*** |  AGPL-3.0, you are granted additional permissions described in the
*** |  REMIND License Exception, version 1.0 (see LICENSE file).
*** |  Contact: remind@pik-potsdam.de
*** SOF ./modules/15_climate/magicc/declarations.gms

Scalar
  s15_forcing_budgetiterationoffset "offset for the calculation of iteratively adjusted budget"
*** to reach specified forcing level in 2100 in W/m^2 -- best guess is 2010 
*** value of respective forcing category minus 0.7
  s15_forcing_budgetiterationoffset_tax "offset for the calculation of iteratively adjusted budget"
*** to reach specified forcing level in 2100 in W/m^2 -- best guess taken from analysis of ERL paper results
s15_tempOffset2010 "mean temperature in 2010 from MAGICC"
;

parameters
p15_oghgf_pfc    	"exogenous forcings from RCP all in W/m^2: PFCs",
p15_oghgf_hfc	 	"exogenous forcings from RCP: HFCs",
p15_oghgf_sf6		"exogenous forcings from RCP: SF6",
p15_oghgf_montreal	"exogenous forcings from RCP: montreal gases",
p15_oghgf_o3str		"exogenous forcings from RCP: stratospheric ozone",
p15_oghgf_luc		"exogenous forcings from RCP: albedo change due to land-use change",
p15_oghgf_crbbb		"exogenous forcings from RCP: carbonaceous aerosols from biomass burning",
p15_oghgf_ffbc		"exogenous forcings from RCP: black carbon from fossil fuels",
p15_oghgf_ffoc		"exogenous forcings from RCP: organic carbon from fossil fuels",
p15_oghgf_o3trp		"exogenous forcings from RCP: tropospheric ozone",
p15_oghgf_h2ostr	"exogenous forcings from RCP: stratospheric water vapor",
p15_oghgf_minaer	"exogenous forcings from RCP: mineral dust",
p15_oghgf_nitaer	"exogenous forcings from RCP: nitrates",
p15_emicapregi(tall,all_regi)  "regional emission caps, used for calculation of global emission cap",
p15_forc_magicc(tall) "actual radiative forcing as calculated by magicc [W/m^2]"
p15_gmt_conv          "global mean temperature convergence"    
p15_gmt0(tall)        "global mean temperature convergence saved for the next iteration"
;

scalars
s15_gr_forc_kyo      "guardrail for 450 ppm Kyoto forcing, adapted between negishi iterations - dummy parameter, only needed to prevent gdx errors",
s15_gr_forc_kyo_nte  "guardrail for 550 ppm Kyoto forcing, adapted between negishi iterations - dummy parameter, only needed to prevent gdx errors",

s15_gr_forc_nte      "not to exceed radiative forcing target from 2100 on [W/m^2]",
s15_gr_forc_os       "overshoot (os) radiative forcing target (guardrail = gr) from 2100 on [W/m^2]"
s15_rcpCluster       " clustering of rcp_scen for the iterative traget adjustment"
;

*** EOF ./modules/15_climate/magicc/declarations.gms
