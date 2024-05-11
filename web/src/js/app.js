// Import necessary Firebase functions directly in app.js
import { signInWithPopup, signOut } from 'https://www.gstatic.com/firebasejs/10.11.1/firebase-auth.js';
import { auth, provider } from './config.js';  // Importing auth and provider from config.js


$(document).ready(function() {
    // Google login event
    $("#google-login").click(function() {
        signInWithPopup(auth, provider)
          .then((result) => {
            const user = result.user;
            // Update UI
            $("#google-login").hide();
            $("#user-name").text(user.displayName || user.email).show();
            $("#logout").show();
            console.log('Google sign-in successful for:', user.email);
        }).catch((error) => {
            console.error('Google sign-in error:', error.message);
        });
    });

    // Logout event
    $("#logout").click(function() {
        signOut(auth).then(() => {
            // Update UI
            $("#google-login").show();
            $("#user-name").hide();
            $("#logout").hide();
            console.log('Logged out successfully');
        }).catch((error) => {
            console.error("Sign out failed:", error.message);
        });
    });
});