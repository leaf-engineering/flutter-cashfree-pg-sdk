
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfcardpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfdropcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfnetbankingpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfsubscriptioncheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfupi.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfupipayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptionconstants.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';

import '../cfcard/cfcardwidget.dart';
import '../cfpayment/cfpayment.dart';

class CFPaymentGatewayService {
  static final CFPaymentGatewayService _singleton = CFPaymentGatewayService._internal();

  factory CFPaymentGatewayService() {
    return _singleton;
  }

  CFPaymentGatewayService._internal();

  static void Function(String)? verifyPayment;
  static void Function(CFErrorResponse, String)? onError;

  setCallback(final void Function(String) vp, final void Function(CFErrorResponse, String) error) {
    verifyPayment = vp;
    onError = error;

    // Create Method channel here
    MethodChannel methodChannel = const MethodChannel('flutter_cashfree_pg_sdk');
    methodChannel.invokeMethod("response").then((value) {
      if(value != null) {
        final body = json.decode(value);
        var status = body["status"] as String;
        switch (status) {
          case "exception":
            var data = body["data"] as Map<String, dynamic>;
            _createErrorResponse(data["message"] as String, null, null, null);
            break;
          case "success":
            var data = body["data"] as Map<String, dynamic>;
            verifyPayment!(data["order_id"] as String);
            break;
          case "failed":
            var data = body["data"] as Map<String, dynamic>;
            var errorResponse = CFErrorResponse(
                data["status"] as String, data["message"] as String,
                data["code"] as String, data["type"] as String);
            onError!(errorResponse, data["order_id"] as String);
            break;
        }
      }
    });
  }

  // TODO: take id for flutter web

  doPayment(CFPayment cfPayment) {
    if(verifyPayment == null || onError == null) {
      throw CFException(CFExceptionConstants.CALLBACK_NOT_SET);
    }

    Map<String, dynamic> data = <String, dynamic>{};

    if(cfPayment is CFCardPayment) {
      CFCardPayment cfCardPayment = cfPayment;
      _initiateCardPayment(cfCardPayment);
    } else {
      if (cfPayment is CFDropCheckoutPayment) {
        CFDropCheckoutPayment dropCheckoutPayment = cfPayment;
        data = _convertToMap(dropCheckoutPayment);
      } else if (cfPayment is CFWebCheckoutPayment) {
        CFWebCheckoutPayment webCheckoutPayment = cfPayment;
        data = _convertToWebCheckoutMap(webCheckoutPayment);
      } else if(cfPayment is CFUPIPayment) {
        CFUPIPayment cfupiPayment = cfPayment;
        data = _convertToUPItMap(cfupiPayment);
      } else if (cfPayment is CFNetbankingPayment) {
        CFNetbankingPayment cfNetbankingPayment = cfPayment;
        data = _convertToNetbankingMap(cfNetbankingPayment);
      } else if (cfPayment is CFSubscriptionPayment) {
        CFSubscriptionPayment cfSubscriptionPayment = cfPayment;
        data = _convertToSubscriptionCheckoutMap(cfSubscriptionPayment);
      }

      // Create Method channel here
      MethodChannel methodChannel = const MethodChannel(
          'flutter_cashfree_pg_sdk');
      if (cfPayment is CFDropCheckoutPayment) {
        methodChannel.invokeMethod("doPayment", data).then((value) {
          responseMethod(value);
        });
      } else if (cfPayment is CFWebCheckoutPayment) {
        methodChannel.invokeMethod("doWebPayment", data).then((value) {
          responseMethod(value);
        });
      } else if(cfPayment is CFUPIPayment) {
        if(cfPayment.getUPI().getChannel() == CFUPIChannel.INTENT_WITH_UI) {
          methodChannel.invokeMethod("doUPIPaymentWithUI", data).then((value) {
            responseMethod(value);
          });
        } else {
          methodChannel.invokeMethod("doUPIPayment", data).then((value) {
            responseMethod(value);
          });
        }
      } else if (cfPayment is CFNetbankingPayment) {
        methodChannel.invokeMethod("doNetbankingPayment", data).then((value) {
          responseMethod(value);
        });
      } else if (cfPayment is CFSubscriptionPayment) {
        methodChannel.invokeMethod("doSubscriptionPayment", data).then((value) {
          responseSubscriptionMethod(value);
        });
      }
    }
  }

  void responseMethod(dynamic value) {
    if(value != null) {
      final body = json.decode(value);
      var status = body["status"] as String;
      switch (status) {
        case "exception":
          var data = body["data"] as Map<String, dynamic>;
          _createErrorResponse(data["message"] as String, null, null, null);
          break;
        case "success":
          var data = body["data"] as Map<String, dynamic>;
          verifyPayment!(data["order_id"] as String);
          break;
        case "failed":
          var data = body["data"] as Map<String, dynamic>;
          var errorResponse = CFErrorResponse(
              data["status"] as String, data["message"] as String,
              data["code"] as String, data["type"] as String);
          onError!(errorResponse, data["order_id"] as String);
          break;
      }
    }
  }

  void responseSubscriptionMethod(dynamic value) {
    if(value != null) {
      final body = json.decode(value);
      var status = body["status"] as String;
      switch (status) {
        case "exception":
          var data = body["data"] as Map<String, dynamic>;
          var cfErrorResponse = CFErrorResponse("FAILED", data["message"] as String, "invalid_request", "invalid_request");
          onError!(cfErrorResponse, "");
          break;
        case "success":
          var data = body["data"] as Map<String, dynamic>;
          final subscriptionId = data["subscriptionId"] ?? data["order_id"];
          if (subscriptionId is String && subscriptionId.isNotEmpty) {
            verifyPayment!(subscriptionId);
          }else {
            debugPrint("No valid subscriptionId or order_id found in response.");
          }
          break;
        case "failed":
          var data = body["data"] as Map<String, dynamic>;
          var errorResponse = CFErrorResponse(
              data["status"] as String, data["message"] as String,
              data["code"] as String, data["type"] as String);
          onError!(errorResponse, "");
          break;
      }
    }
  }

  void _initiateCardPayment(CFCardPayment cfCardPayment) {
    Map<String, dynamic> session = {
      "environment": cfCardPayment.getSession().getEnvironment(),
      "order_id": cfCardPayment.getSession().getOrderId(),
      "payment_session_id": cfCardPayment.getSession()
          .getPaymentSessionId(),
    };

    if(cfCardPayment.getCard().getCardNumber() != null) {
      (cfCardPayment
          .getCard()
          .getCardNumber()
          ?.key as GlobalKey<CFCardWidgetState>).currentState?.completePayment(
          verifyPayment!,
          onError!,
          cfCardPayment.getCard().getCardCvv(),
          cfCardPayment.getCard().getCardHolderName(),
          cfCardPayment.getCard().getCardExpiryMonth(),
          cfCardPayment.getCard().getCardExpiryYear(),
          session,
          cfCardPayment.getSavePaymentMethodFlag(),
          cfCardPayment.getCard().getInstrumentId());
    } else {
      _completePaymentWithInstrumentId(
          verifyPayment!,
          onError!,
          cfCardPayment.getCard().getCardCvv(),
          session,
          cfCardPayment.getCard().getInstrumentId() ?? "");
    }
  }

  void _completePaymentWithInstrumentId(final void Function(String) verifyPayment,
      final void Function(CFErrorResponse, String) onError,
      String card_cvv,
      Map<String, dynamic> session,
      String instrument_id) {

    Map<String, String> card = {};

      card = {
        "instrument_id": instrument_id,
        "card_cvv": card_cvv,
      };

    Map<String, dynamic> data = {
      "session": session,
      "card": card,
      "save_payment_method": false,
    };

    // Create Method channel here
    MethodChannel methodChannel = const MethodChannel(
        'flutter_cashfree_pg_sdk');
    methodChannel.invokeMethod("doCardPayment", data).then((value) {
      if(value != null) {
        final body = json.decode(value);
        var status = body["status"] as String;
        switch (status) {
          case "exception":
            var data = body["data"] as Map<String, dynamic>;
            var cfErrorResponse = CFErrorResponse("FAILED", data["message"] as String, "invalid_request", "invalid_request");
            onError(cfErrorResponse, session["order_id"] ?? "order_id_not_found");
            break;
          case "success":
            var data = body["data"] as Map<String, dynamic>;
            verifyPayment(data["order_id"] as String);
            break;
          case "failed":
            var data = body["data"] as Map<String, dynamic>;
            var errorResponse = CFErrorResponse(
                data["status"] as String, data["message"] as String,
                data["code"] as String, data["type"] as String);
            onError(errorResponse, data["order_id"] as String);
            break;
        }
      }
    });
  }

  Map<String, dynamic> _convertToNetbankingMap(CFNetbankingPayment cfNetbankingPayment) {
    Map<String, dynamic> session = {
      "environment": cfNetbankingPayment.getSession().getEnvironment(),
      "order_id": cfNetbankingPayment.getSession().getOrderId(),
      "payment_session_id": cfNetbankingPayment.getSession()
          .getPaymentSessionId(),
    };

    Map<String, String> netbanking = {
      "channel": cfNetbankingPayment.getNetbanking().getChannel(),
      "net_banking_code": cfNetbankingPayment.getNetbanking().getBankCode().toString(),
    };

    Map<String, dynamic> data = {
      "session": session,
      "net_banking": netbanking,
    };
    return data;
  }

  Map<String, dynamic> _convertToUPItMap(CFUPIPayment cfupiPayment) {
    Map<String, dynamic> session = {
      "environment": cfupiPayment.getSession().getEnvironment(),
      "order_id": cfupiPayment.getSession().getOrderId(),
      "payment_session_id": cfupiPayment.getSession()
          .getPaymentSessionId(),
    };

    Map<String, String> upi = {
      "channel": cfupiPayment.getUPI().getChannel() == CFUPIChannel.COLLECT ? "collect" : "intent",
      "upi_id": cfupiPayment.getUPI().getChannel() == CFUPIChannel.INTENT_WITH_UI ? "" : cfupiPayment.getUPI().getUPIID(),
    };

    Map<String, dynamic> data = {
      "session": session,
      "upi": upi,
    };
    return data;
  }

  Map<String, dynamic> _convertToWebCheckoutMap(CFWebCheckoutPayment cfWebCheckoutPayment) {
    Map<String, dynamic> session = {
      "environment": cfWebCheckoutPayment.getSession().getEnvironment(),
      "order_id": cfWebCheckoutPayment.getSession().getOrderId(),
      "payment_session_id": cfWebCheckoutPayment.getSession()
          .getPaymentSessionId(),
    };

    Map<String, dynamic> theme = {
      "navigationBarBackgroundColor": cfWebCheckoutPayment.getTheme().getNavigationBarBackgroundColor(),
      "navigationBarTextColor": cfWebCheckoutPayment.getTheme().getNavigationBarTextColor(),
      "buttonBackgroundColor": cfWebCheckoutPayment.getTheme().getButtonBackgroundColor(),
      "buttonTextColor": cfWebCheckoutPayment.getTheme().getButtonTextColor(),
      "primaryTextColor": cfWebCheckoutPayment.getTheme().getPrimaryTextColor(),
      "secondaryTextColor": cfWebCheckoutPayment.getTheme().getSecondaryTextColor(),
      "primaryFont": cfWebCheckoutPayment.getTheme().getPrimaryFont(),
      "secondaryFont": cfWebCheckoutPayment.getTheme().getSecondaryFont()
    };

    Map<String, dynamic> data = {
      "session": session,
      "theme": theme
    };
    return data;
  }

  Map<String, dynamic> _convertToSubscriptionCheckoutMap(CFSubscriptionPayment cfSubscriptionPayment) {
    Map<String, dynamic> session = {
      "environment": cfSubscriptionPayment.getSession().getEnvironment(),
      "subscription_id": cfSubscriptionPayment.getSession().getSubscriptionId(),
      "subscription_session_id": cfSubscriptionPayment.getSession().getSubscriptionSessionID()
    };

    Map<String, dynamic> theme = {
      "navigationBarBackgroundColor": cfSubscriptionPayment.getTheme().getNavigationBarBackgroundColor(),
      "navigationBarTextColor": cfSubscriptionPayment.getTheme().getNavigationBarTextColor()
    };

    Map<String, dynamic> data = {
      "session": session,
      "theme": theme
    };
    return data;
  }

  Map<String, dynamic> _convertToMap(CFDropCheckoutPayment cfDropCheckoutPayment) {

    Map<String, dynamic> session = {
      "environment": cfDropCheckoutPayment.getSession().getEnvironment(),
      "order_id": cfDropCheckoutPayment.getSession().getOrderId(),
      "payment_session_id": cfDropCheckoutPayment.getSession().getPaymentSessionId(),
    };

    Map<String, dynamic> paymentComponents = {
      "components": cfDropCheckoutPayment.getPaymentComponent().getComponents()
    };

    Map<String, dynamic> theme = {
      "navigationBarBackgroundColor": cfDropCheckoutPayment.getTheme().getNavigationBarBackgroundColor(),
      "navigationBarTextColor": cfDropCheckoutPayment.getTheme().getNavigationBarTextColor(),
      "buttonBackgroundColor": cfDropCheckoutPayment.getTheme().getButtonBackgroundColor(),
      "buttonTextColor": cfDropCheckoutPayment.getTheme().getButtonTextColor(),
      "primaryTextColor": cfDropCheckoutPayment.getTheme().getPrimaryTextColor(),
      "secondaryTextColor": cfDropCheckoutPayment.getTheme().getSecondaryTextColor(),
      "primaryFont": cfDropCheckoutPayment.getTheme().getPrimaryFont(),
      "secondaryFont": cfDropCheckoutPayment.getTheme().getSecondaryFont()
    };

    Map<String, dynamic> data = {
      "session": session,
      "paymentComponents": paymentComponents,
      "theme": theme
    };
    return data;
  }

  _createErrorResponse(String? message, String? code, String? type, String? orderId) {
    var cfErrorResponse = CFErrorResponse("FAILED", message ?? "something went wrong", code ?? "invalid_request", type ?? "invalid_request");
    onError!(cfErrorResponse, orderId ?? "order_id_not_found");
  }
}