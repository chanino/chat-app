// Import necessary Firebase functions directly in app.js
import { signInWithPopup, signOut } from 'https://www.gstatic.com/firebasejs/10.11.1/firebase-auth.js';
import { auth, provider } from './config.js';  // Importing auth and provider from config.js

$(document).ready(function() {
    let userToken = null;

    // Google login event
    $("#google-login").click(function() {
        signInWithPopup(auth, provider)
            .then((result) => {
                const user = result.user;
                // Update UI
                $("#google-login").hide();
                $("#user-name").text(user.displayName || user.email).show();
                $("#logout").show();
                $("#user-content").show();
                console.log('Google sign-in successful for:', user.email);

                // Get the ID token of the logged-in user
                user.getIdToken().then(function(token) {
                    userToken = token;
                    console.log(token);
                }).catch((error) => {
                    console.error('Error getting ID token:', error.message);
                });
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
            $("#user-content").hide();
            userToken = null;
            console.log('Logged out successfully');
        }).catch((error) => {
            console.error("Sign out failed:", error.message);
        });
    });

    // Handle URL form submission
    $("#url-form").submit(function(event) {
        event.preventDefault();
        if (!userToken) {
            alert("You must be logged in to submit a URL.");
            return;
        }

        const url = $("#url-input").val();

        $.ajax({
            url: 'https://7zl9faran2.execute-api.us-west-2.amazonaws.com/prod/message',
            type: 'POST',
            headers: {
                'Authorization': `Bearer ${userToken}`
            },
            data: JSON.stringify({ 
                body: JSON.stringify({ message: url })
            }),
            success: function(response) {
                console.log('URL submitted successfully:', response);
                alert('URL submitted successfully!');
            },
            error: function(xhr, status, error) {
                console.error('Error submitting URL:', error);
                alert('Error submitting URL.');
            }
        });
    });

});

